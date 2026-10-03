require "rails_helper"

# Guards the eval set itself, so a typo in an id cannot silently turn a
# question into a permanent miss. Needs no API key.
RSpec.describe "evals/retrieval.yml" do
  let(:cases) { YAML.load_file(Rails.root.join("evals/retrieval.yml"), symbolize_names: true) }
  let(:seed_ids) do
    YAML.load_file(Rails.root.join("db/seeds/knowledge_base.yml"), symbolize_names: true).map { |entry| entry.fetch(:id) }
  end

  it "only expects documents that exist in the seeds" do
    unknown = cases.flat_map { |entry| entry.fetch(:expected) } - seed_ids

    expect(unknown).to be_empty
  end

  it "has a question, an expected list and at least one tag for every case" do
    expect(cases).to all(include(question: be_present, expected: be_an(Array), tags: be_present))
  end

  it "does not repeat questions" do
    questions = cases.map { |entry| entry.fetch(:question).downcase.strip }

    expect(questions).to eq(questions.uniq)
  end

  it "has enough scored questions, and some unanswerable ones" do
    scored, unscored = cases.partition { |entry| entry.fetch(:expected).any? }

    expect(scored.size).to be >= 30
    expect(unscored.size).to be >= 3
  end
end
