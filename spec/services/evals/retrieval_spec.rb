require "rails_helper"

RSpec.describe Evals::Retrieval do
  # A vector made of weighted axes, e.g. mix(0 => 1.0, 1 => 0.5).
  def mix(weights)
    Array.new(Chunk::EMBEDDING_DIMENSIONS, 0.0).tap { |vector| weights.each { |axis, weight| vector[axis] = weight } }
  end

  def seed_document(source_id, axis)
    create(:document, source: "seed", source_id: source_id, title: source_id.titleize).tap do |document|
      create(:chunk, document: document, position: 0, embedding: mix(axis => 1.0))
    end
  end

  def eval_case(question, expected, tags = [ "faq" ])
    described_class::Case.new(question: question, expected: expected, tags: tags)
  end

  # Four documents on four orthogonal axes; a question's vector decides how
  # close it is to each.
  before do
    seed_document("hours", 0)
    seed_document("parking", 1)
    seed_document("payment", 2)
    seed_document("privacy", 3)
  end

  let(:question_vectors) do
    {
      "first" => mix(0 => 1.0),                                   # hours 1st
      "third" => mix(0 => 1.0, 1 => 0.6, 2 => 0.3),               # payment 3rd
      "fourth" => mix(0 => 1.0, 1 => 0.6, 2 => 0.3, 3 => 0.1),    # privacy 4th
      "unanswerable" => mix(1 => 1.0)
    }
  end

  let(:cases) do
    [
      eval_case("first", [ "hours" ], %w[faq easy]),
      eval_case("third", [ "payment" ], %w[policy]),
      eval_case("fourth", [ "privacy" ], %w[policy]),
      eval_case("unanswerable", [], %w[off_topic])
    ]
  end

  def run(cases: self.cases, k: 3)
    embedded = stub_embeddings { |text| question_vectors.fetch(text.split("query: ").last) }
    report = described_class.new(cases: cases, k: k).call
    [ report, embedded ]
  end

  it "ranks the nearest documents for each question" do
    report, = run

    expect(report.outcomes.map(&:rank)).to eq([ 1, 3, 4, nil ])
    expect(report.outcomes[1].hits.first(3).map(&:source_id)).to eq(%w[hours parking payment])
    expect(report.outcomes.first.hits.first).to have_attributes(title: "Hours", distance: be_within(1e-6).of(0))
  end

  it "computes hit@1, hit@K and MRR over the scored questions only" do
    report, = run

    expect(report.overall).to eq(
      "questions" => 3,
      "hit_at_1" => 0.333,
      "hit_at_k" => 0.667,
      "mrr" => ((1 + 1 / 3.0 + 1 / 4.0) / 3).round(3)
    )
    expect(report.misses.map { |outcome| outcome.entry.question }).to eq([ "fourth" ])
    expect(report.unscored.map { |outcome| outcome.entry.question }).to eq([ "unanswerable" ])
  end

  it "breaks the metrics down by tag" do
    report, = run

    expect(report.by_tag.keys).to eq(%w[faq easy policy])
    expect(report.by_tag["faq"]).to include("questions" => 1, "hit_at_1" => 1.0, "hit_at_k" => 1.0, "mrr" => 1.0)
    expect(report.by_tag["policy"]).to include("questions" => 2, "hit_at_1" => 0.0, "hit_at_k" => 0.5)
  end

  it "respects K" do
    report, = run(k: 4)

    expect(report.overall).to include("hit_at_k" => 1.0)
    expect(report.misses).to be_empty
  end

  it "counts a hit when any of several expected documents is found" do
    report, = run(cases: [ eval_case("third", %w[payment parking]) ])

    expect(report.outcomes.sole.rank).to eq(2)
  end

  it "embeds all questions in a single call, as queries" do
    _, embedded = run

    expect(RubyLLM).to have_received(:embed).once
    expect(embedded.first).to eq("task: search result | query: first")
  end

  it "ignores documents from other sources and counts each document once" do
    upload = create(:document, source: "upload", source_id: "hours-copy")
    create(:chunk, document: upload, embedding: mix(0 => 1.0))
    create(:chunk, document: Document.find_by!(source_id: "hours"), position: 1, embedding: mix(0 => 1.0, 1 => 0.1))

    report, = run

    expect(report.outcomes.first.hits.map(&:source_id)).to eq(%w[hours parking payment privacy])
  end

  it "refuses to run when the seeds are missing or not fully embedded" do
    create(:document, source: "seed", source_id: "not-embedded")
    expect { run }.to raise_error(Evals::Retrieval::NotReady, /1 seed documents are not embedded/)

    Document.destroy_all
    expect { run }.to raise_error(Evals::Retrieval::NotReady, /No seed documents/)
  end

  it "summarises the run for the baseline file" do
    report, = run

    expect(report.to_h).to include("model" => Chunk::EMBEDDING_MODEL, "k" => 3, "chunk_max_chars" => 800,
                                   "overall" => report.overall, "by_tag" => report.by_tag)
  end

  it "loads the real dataset" do
    cases = described_class.load_cases

    expect(cases.first).to have_attributes(question: be_present, expected: be_an(Array), tags: be_an(Array))
    expect(cases.count(&:scored?)).to be >= 30
  end
end
