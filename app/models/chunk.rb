# A slice of a Document's body with its embedding, the unit retrieved by RAG.
class Chunk < ApplicationRecord
  EMBEDDING_MODEL = "text-embedding-3-small"
  EMBEDDING_DIMENSIONS = 1536

  belongs_to :document

  has_neighbors :embedding, dimensions: EMBEDDING_DIMENSIONS

  validates :content, :position, presence: true

  # Embeds +texts+ in one provider call and returns one vector per text.
  def self.embed(texts)
    RubyLLM.embed(Array(texts), model: EMBEDDING_MODEL).vectors
  end

  # The +limit+ chunks closest in meaning to +query+, nearest first. Each
  # result responds to +neighbor_distance+ (cosine distance, lower is closer).
  def self.search(query, limit: 5)
    nearest_neighbors(:embedding, embed(query).first, distance: "cosine")
      .includes(:document)
      .limit(limit)
  end
end
