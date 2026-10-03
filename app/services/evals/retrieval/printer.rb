module Evals
  class Retrieval
    # Renders a Report as text for the terminal, with the change against a
    # saved baseline when there is one.
    class Printer
      METRICS = { "hit_at_1" => "hit@1", "hit_at_k" => nil, "mrr" => "MRR" }.freeze

      def initialize(report, baseline: nil)
        @report = report
        @baseline = baseline
      end

      def to_s
        [ header, table, misses, not_first, unscored, distances ].compact.join("\n\n")
      end

      private

      attr_reader :report, :baseline

      def header
        lines = [ "Retrieval eval · #{report.model} · chunks ≤ #{Chunker::MAX_CHARS} chars · " \
                  "#{report.scored.size} scored questions · K=#{report.k}" ]
        lines << "Compared with the baseline of #{baseline['recorded_on']}: #{baseline_description}" if baseline
        lines.join("\n")
      end

      def baseline_description
        same = baseline.values_at("model", "k", "chunk_max_chars") == [ report.model, report.k, Chunker::MAX_CHARS ]
        return "same model, K and chunk size" if same

        "#{baseline['model']}, K=#{baseline['k']}, chunks ≤ #{baseline['chunk_max_chars']} chars"
      end

      def table
        rows = { "overall" => report.overall }.merge(report.by_tag)
        width = rows.keys.map(&:length).max

        heading = format("%-#{width}s  %5s  %-16s%-16s%-16s", "", "n", "hit@1", "hit@#{report.k}", "MRR")
        body = rows.map do |name, metrics|
          cells = METRICS.keys.map { |key| format("%-16s", cell(name, key, metrics[key])) }
          format("%-#{width}s  %5d  %s", name, metrics["questions"], cells.join).rstrip
        end

        [ heading.rstrip, *body ].join("\n")
      end

      def cell(row, key, value)
        previous = baseline && (row == "overall" ? baseline["overall"] : baseline.dig("by_tag", row))&.fetch(key, nil)
        return format("%.3f", value) if previous.nil?

        delta = (value - previous).round(3)
        format("%.3f (%s)", value, delta.zero? ? "=" : format("%+.3f", delta))
      end

      def misses
        return "No misses: every expected document was in the top #{report.k}." if report.misses.empty?

        lines = report.misses.flat_map do |outcome|
          [
            "  \"#{outcome.entry.question}\"",
            "     expected: #{outcome.entry.expected.join(' or ')}" \
              "#{outcome.rank ? " (found at position #{outcome.rank})" : ' (not in the top 10)'}",
            "     got:      #{ranking(outcome.hits.first(report.k))}"
          ]
        end
        [ "Misses (#{report.misses.size}):", *lines ].join("\n")
      end

      # Hits that were outranked: where hit@1 and MRR are lost.
      def not_first
        outranked = report.scored.select { |outcome| outcome.hit_at?(report.k) && outcome.rank > 1 }
        return if outranked.empty?

        lines = outranked.map do |outcome|
          "  \"#{outcome.entry.question}\"\n     found at position #{outcome.rank}, behind: #{ranking(outcome.hits.first(outcome.rank - 1))}"
        end
        [ "Found, but not first (#{outranked.size}):", *lines ].join("\n")
      end

      def unscored
        return if report.unscored.empty?

        lines = report.unscored.map do |outcome|
          "  \"#{outcome.entry.question}\" [#{outcome.entry.tags.join(', ')}]\n     nearest:  #{ranking(outcome.hits.first(1))}"
        end
        [ "No answer in the knowledge base (not scored; shows how close the nearest document still is):", *lines ].join("\n")
      end

      # If these two ranges overlap, a distance cutoff cannot tell "no answer"
      # from "answer found": that call has to be made from the content.
      def distances
        found = report.scored.filter_map { |outcome| outcome.rank && outcome.hits[outcome.rank - 1].distance }.sort
        nearest = report.unscored.filter_map { |outcome| outcome.hits.first&.distance }.sort
        return if found.empty? || nearest.empty?

        "Distances (cosine, lower is closer):\n" \
          "  expected document, when found:        #{range(found)}, median #{format('%.3f', found[found.size / 2])}\n" \
          "  nearest document, when no answer:     #{range(nearest)}"
      end

      def range(values)
        "#{format('%.3f', values.first)} to #{format('%.3f', values.last)}"
      end

      def ranking(hits)
        hits.each_with_index.map { |hit, index| "#{index + 1}. #{hit.source_id} (#{format('%.3f', hit.distance)})" }.join("  ")
      end
    end
  end
end
