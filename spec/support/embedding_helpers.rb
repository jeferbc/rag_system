# Stand-ins for the embeddings API so specs never need a provider key.
module EmbeddingHelpers
  # A unit vector pointing along a single axis. Two vectors with the same
  # +axis+ are identical; different axes are orthogonal (cosine distance 1).
  def axis_vector(axis)
    Array.new(Chunk::EMBEDDING_DIMENSIONS, 0.0).tap { |vector| vector[axis] = 1.0 }
  end

  # Stubs RubyLLM.embed. Each text gets the vector the block returns for it,
  # or a distinct axis vector by default. Returns the list of embedded texts.
  def stub_embeddings
    embedded = []
    allow(RubyLLM).to receive(:embed) do |texts, **|
      vectors = texts.map do |text|
        embedded << text
        block_given? ? yield(text) : axis_vector(embedded.size - 1)
      end
      RubyLLM::Embedding.new(vectors: vectors, model: Chunk::EMBEDDING_MODEL)
    end
    embedded
  end
end
