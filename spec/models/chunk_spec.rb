require "rails_helper"

RSpec.describe Chunk do
  describe ".embed" do
    it "embeds a batch of texts with the configured model and vector size" do
      stub_embeddings

      vectors = described_class.embed([ "one", "two" ])

      expect(vectors).to eq([ axis_vector(0), axis_vector(1) ])
      expect(RubyLLM).to have_received(:embed).with([ "one", "two" ], model: Chunk::EMBEDDING_MODEL, dimensions: 1536)
    end
  end

  describe ".embed_documents and .embed_query" do
    it "use the asymmetric retrieval prompts, carrying the title with every chunk" do
      embedded = stub_embeddings

      described_class.embed_documents("Elena Marsh", [ "Trata la ansiedad.", "Atiende en inglés." ])
      described_class.embed_query("psicóloga para la ansiedad")

      expect(embedded).to eq([
        "title: Elena Marsh | text: Trata la ansiedad.",
        "title: Elena Marsh | text: Atiende en inglés.",
        "task: search result | query: psicóloga para la ansiedad"
      ])
    end
  end

  describe ".search" do
    it "returns the chunks nearest to the query embedding, closest first" do
      anxiety = create(:chunk, content: "Treats anxiety", embedding: axis_vector(1))
      near_anxiety = create(:chunk, content: "Treats panic", embedding: axis_vector(1).tap { |v| v[2] = 0.5 })
      create(:chunk, content: "Parking information", embedding: axis_vector(3))
      stub_embeddings { axis_vector(1) }

      results = described_class.search("help with anxiety", limit: 2)

      expect(results.to_a).to eq([ anxiety, near_anxiety ])
      expect(results.first.neighbor_distance).to be_within(1e-6).of(0)
    end
  end
end
