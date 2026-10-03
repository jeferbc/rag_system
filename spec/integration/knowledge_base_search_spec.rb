require "rails_helper"

# The whole offline pipeline: seed -> chunk -> embed -> pgvector search.
# Embeddings are faked with a bag-of-words vector (each word lights up one
# dimension), which is crude but makes cosine distance track word overlap, so
# the real HNSW index and nearest-neighbor query run against plausible data.
RSpec.describe "Knowledge base search" do
  def bag_of_words_vector(text)
    vector = Array.new(Chunk::EMBEDDING_DIMENSIONS, 0.0)
    text.downcase.scan(/\p{L}{4,}/).each { |word| vector[Zlib.crc32(word) % vector.size] += 1.0 }
    vector
  end

  before do
    stub_embeddings { |text| bag_of_words_vector(text) }
    original = $stdout
    $stdout = StringIO.new
    load Rails.root.join("db/seeds.rb")
    $stdout = original
    Document.find_each { |document| IngestDocumentJob.perform_now(document) }
  end

  it "ingests every seeded document into ordered, embedded chunks" do
    expect(Document.where.missing(:chunks)).to be_empty
    expect(Chunk.pluck(:content).map(&:length)).to all(be <= Chunker::MAX_CHARS)
    Document.find_each do |document|
      expect(document.chunks.map(&:position)).to eq((0...document.chunks.size).to_a)
    end
  end

  # Word overlap cannot tell "offers English" from "does not offer English";
  # that judgement is left to real embeddings and the evals phase.
  it "ranks anxiety specialists first for a patient's question" do
    results = Chunk.search("psicóloga para la ansiedad que atienda en inglés", limit: 3)

    expect(results.first.document.category).to eq("psychologist")
    expect(results.first.content).to include("ansiedad")
    expect(results.map { |chunk| chunk.document.psychologist_ref }).to include("psy-101-elena-marsh")
    expect(results.map(&:neighbor_distance)).to eq(results.map(&:neighbor_distance).sort)
  end

  it "finds the relevant policy for a cancellation question" do
    results = Chunk.search("cancelar o cambiar una cita con menos de 24 horas de antelación", limit: 1)

    expect(results.first.document.source_id).to eq("policy-cancellation-and-rescheduling")
  end
end
