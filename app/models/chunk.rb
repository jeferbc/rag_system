# A slice of a Document's body with its embedding, the unit retrieved by RAG.
class Chunk < ApplicationRecord
  # Any RubyLLM embedding model that can output 1536 dimensions. Changing the
  # model makes existing vectors incomparable: re-embed everything with
  # `bin/rails documents:ingest ALL=1`.
  EMBEDDING_MODEL = ENV.fetch("EMBEDDING_MODEL", "gemini-embedding-2")
  EMBEDDING_DIMENSIONS = 1536

  belongs_to :document

  has_neighbors :embedding, dimensions: EMBEDDING_DIMENSIONS

  validates :content, :position, presence: true

  # Embeds the chunks of one document. The "title: … | text: …" form is the
  # retrieval format Google documents for gemini-embedding-2; it also keeps a
  # fragment like "atiende en inglés" tied to the psychologist it describes.
  # Other providers simply see it as text.
  def self.embed_documents(title, contents)
    embed(contents.map { |content| "title: #{title} | text: #{content}" })
  end

  # Embeds patients' questions so that they land near the documents that
  # answer them (asymmetric retrieval). One provider call for all of them.
  def self.embed_queries(queries)
    embed(queries.map { |query| "task: search result | query: #{query}" })
  end

  def self.embed_query(query)
    embed_queries([ query ]).first
  end

  # Embeds +texts+ in one provider call and returns one vector per text.
  def self.embed(texts)
    RubyLLM.embed(texts, model: EMBEDDING_MODEL, dimensions: EMBEDDING_DIMENSIONS).vectors
  end

  # The +limit+ chunks closest to an already-embedded query, nearest first.
  # Each result responds to +neighbor_distance+ (cosine distance, lower is
  # closer). Chainable, e.g. Chunk.where(...).nearest_to(vector).
  def self.nearest_to(vector, limit: 5)
    nearest_neighbors(:embedding, vector, distance: "cosine").includes(:document).limit(limit)
  end

  # The +limit+ chunks closest in meaning to +query+.
  def self.search(query, limit: 5)
    nearest_to(embed_query(query), limit: limit)
  end
end
