require "rails_helper"

RSpec.describe Evals::Retrieval::Printer do
  def outcome(question, expected, tags, hit_ids)
    hits = hit_ids.each_with_index.map { |id, index| Evals::Retrieval::Hit.new(id, id.titleize, 0.1 * (index + 1)) }
    Evals::Retrieval::Outcome.new(entry: Evals::Retrieval::Case.new(question: question, expected: expected, tags: tags),
                                  hits: hits)
  end

  let(:report) do
    Evals::Retrieval::Report.new(k: 3, model: "gemini-embedding-2", outcomes: [
      outcome("puedo pagar con tarjeta?", [ "policy-payment" ], [ "policy" ], %w[policy-payment faq-languages]),
      outcome("cuanto dura", [ "faq-length" ], [ "faq" ], %w[faq-first faq-online policy-payment faq-length]),
      outcome("que clima hace", [], [ "off_topic" ], %w[faq-languages]),
      outcome("graban?", [ "policy-online" ], [ "policy" ], %w[faq-online policy-online])
    ])
  end

  it "prints the metrics, the misses and the unscored questions" do
    text = described_class.new(report).to_s

    expect(text).to include("Retrieval eval · gemini-embedding-2 · chunks ≤ 800 chars · 3 scored questions · K=3")
    expect(text).to match(/^overall\s+3\s+0\.333\s+0\.667\s+0\.583$/)
    expect(text).to match(/^policy\s+2\s+0\.500\s+1\.000\s+0\.750$/)
    expect(text).to include("Found, but not first (1):", '"graban?"', "found at position 2, behind: 1. faq-online (0.100)")
    expect(text).to include("Misses (1):", '"cuanto dura"', "expected: faq-length (found at position 4)",
                            "got:      1. faq-first (0.100)  2. faq-online (0.200)  3. policy-payment (0.300)")
    expect(text).to include('"que clima hace" [off_topic]', "nearest:  1. faq-languages (0.100)")
    expect(text).to include("expected document, when found:        0.100 to 0.400, median 0.200",
                            "nearest document, when no answer:     0.100 to 0.100")
  end

  it "shows the change against a baseline" do
    baseline = {
      "model" => "gemini-embedding-2", "k" => 3, "chunk_max_chars" => 800, "recorded_on" => "2026-10-03",
      "overall" => { "questions" => 3, "hit_at_1" => 0.333, "hit_at_k" => 1.0, "mrr" => 0.5 },
      "by_tag" => { "policy" => { "questions" => 1, "hit_at_1" => 1.0, "hit_at_k" => 1.0, "mrr" => 1.0 } }
    }

    text = described_class.new(report, baseline: baseline).to_s

    expect(text).to include("Compared with the baseline of 2026-10-03: same model, K and chunk size")
    expect(text).to match(/^overall\s+3\s+0\.333 \(=\)\s+0\.667 \(-0\.333\)\s+0\.583 \(\+0\.083\)$/)
    expect(text).to match(/^faq\s+1\s+0\.000\s+0\.000\s+0\.250$/)
  end

  it "says so when the baseline was recorded with a different setup" do
    baseline = { "model" => "text-embedding-3-small", "k" => 3, "chunk_max_chars" => 400, "recorded_on" => "2026-10-01",
                 "overall" => {}, "by_tag" => {} }

    expect(described_class.new(report, baseline: baseline).to_s)
      .to include("baseline of 2026-10-01: text-embedding-3-small, K=3, chunks ≤ 400 chars")
  end

  it "celebrates a clean run" do
    clean = Evals::Retrieval::Report.new(k: 3, model: "m", outcomes: report.outcomes.first(1))

    expect(described_class.new(clean).to_s).to include("No misses: every expected document was in the top 3.")
  end
end
