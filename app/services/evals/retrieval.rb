module Evals
  # Measures retrieval quality: for each question in evals/retrieval.yml, does
  # the nearest-neighbor search return the document that answers it?
  #
  # Runs against the seed documents only, so anything uploaded to a
  # development database cannot skew the ranking, and compares documents
  # rather than chunks, because chunk ids change on every re-ingestion.
  class Retrieval
    DATASET = Rails.root.join("evals/retrieval.yml")
    SOURCE = "seed"
    # How deep to look for the expected document. Deeper than K so that MRR
    # can tell "ranked 4th" from "nowhere near".
    RANK_DEPTH = 10
    # A document has several chunks; over-fetch so RANK_DEPTH distinct
    # documents survive de-duplication.
    CHUNKS_PER_DOCUMENT = 4

    class NotReady < StandardError; end

    Case = Data.define(:question, :expected, :tags) do
      def scored? = expected.any?
    end

    Hit = Data.define(:source_id, :title, :distance)

    def self.load_cases(path = DATASET)
      YAML.load_file(path, symbolize_names: true).map do |entry|
        Case.new(question: entry.fetch(:question), expected: entry.fetch(:expected), tags: entry.fetch(:tags))
      end
    end

    def initialize(cases: self.class.load_cases, k: 3)
      @cases = cases
      @k = k
    end

    def call
      ensure_ready!

      vectors = Chunk.embed_queries(cases.map(&:question))
      outcomes = cases.zip(vectors).map { |entry, vector| Outcome.new(entry: entry, hits: nearest_documents(vector)) }

      Report.new(k: k, model: Chunk::EMBEDDING_MODEL, outcomes: outcomes)
    end

    private

    attr_reader :cases, :k

    def nearest_documents(vector)
      seed_chunks.nearest_to(vector, limit: RANK_DEPTH * CHUNKS_PER_DOCUMENT)
                 .map { |chunk| Hit.new(chunk.document.source_id, chunk.document.title, chunk.neighbor_distance) }
                 .uniq(&:source_id)
                 .first(RANK_DEPTH)
    end

    def seed_chunks
      Chunk.joins(:document).where(documents: { source: SOURCE })
    end

    # A missing or half-embedded knowledge base would score as bad retrieval.
    def ensure_ready!
      seeds = Document.from_source(SOURCE)
      raise NotReady, "No seed documents. Run `bin/rails db:seed` first." if seeds.none?

      missing = seeds.where.missing(:chunks).count
      return if missing.zero?

      raise NotReady, "#{missing} seed documents are not embedded. Run `bin/rails documents:ingest` first."
    end
  end
end
