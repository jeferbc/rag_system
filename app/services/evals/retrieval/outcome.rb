module Evals
  class Retrieval
    # What retrieval returned for one question: the nearest documents, in order.
    Outcome = Data.define(:entry, :hits) do
      # 1-based position of the first expected document, or nil if it is not
      # among the hits.
      def rank
        position = hits.index { |hit| entry.expected.include?(hit.source_id) }
        position && position + 1
      end

      def hit_at?(k)
        !rank.nil? && rank <= k
      end

      def reciprocal_rank
        rank ? 1.0 / rank : 0.0
      end
    end
  end
end
