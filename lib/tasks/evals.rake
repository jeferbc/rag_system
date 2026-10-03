namespace :evals do
  desc "Score retrieval against evals/retrieval.yml (K=3 by default; SAVE_BASELINE=1 records the result). Calls the embeddings API."
  task retrieval: :environment do
    baseline_path = Rails.root.join("evals/baseline.json")
    baseline = JSON.parse(baseline_path.read) if baseline_path.exist?

    report = Evals::Retrieval.new(k: ENV.fetch("K", 3).to_i).call
    puts Evals::Retrieval::Printer.new(report, baseline: baseline)

    if ENV["SAVE_BASELINE"].present?
      baseline_path.write("#{JSON.pretty_generate(report.to_h.merge('recorded_on' => Date.current.iso8601))}\n")
      puts "\nBaseline saved to evals/baseline.json"
    end
  rescue Evals::Retrieval::NotReady, RubyLLM::ConfigurationError => error
    abort error.message.lines.first
  rescue RubyLLM::RateLimitError => error
    # Each question counts as one request against the provider's per-minute quota.
    abort "Embedding rate limit reached; wait a minute and run it again.\n#{error.message.lines.first}"
  end
end
