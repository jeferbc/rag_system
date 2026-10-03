module Evals
  class Retrieval
    # The outcomes of one eval run, with the metrics computed from them.
    #
    # - hit@1 / hit@K: share of questions whose expected document is the first
    #   result / among the first K.
    # - MRR (mean reciprocal rank): average of 1/position of the expected
    #   document, 0 when it was not found. Rewards ranking it higher.
    Report = Data.define(:k, :model, :outcomes) do
      def scored = outcomes.select { |outcome| outcome.entry.scored? }
      def unscored = outcomes.reject { |outcome| outcome.entry.scored? }
      def misses = scored.reject { |outcome| outcome.hit_at?(k) }

      def overall
        metrics_for(scored)
      end

      # Metrics per tag, in order of first appearance in the dataset.
      def by_tag
        scored.flat_map { |outcome| outcome.entry.tags }.uniq.index_with do |tag|
          metrics_for(scored.select { |outcome| outcome.entry.tags.include?(tag) })
        end
      end

      # The comparable summary that gets saved as the baseline.
      def to_h
        {
          "model" => model,
          "k" => k,
          "chunk_max_chars" => Chunker::MAX_CHARS,
          "overall" => overall,
          "by_tag" => by_tag
        }
      end

      private

      def metrics_for(group)
        return { "questions" => 0, "hit_at_1" => 0.0, "hit_at_k" => 0.0, "mrr" => 0.0 } if group.empty?

        {
          "questions" => group.size,
          "hit_at_1" => share(group) { |outcome| outcome.hit_at?(1) },
          "hit_at_k" => share(group) { |outcome| outcome.hit_at?(k) },
          "mrr" => (group.sum(&:reciprocal_rank) / group.size).round(3)
        }
      end

      def share(group, &block)
        (group.count(&block).to_f / group.size).round(3)
      end
    end
  end
end
