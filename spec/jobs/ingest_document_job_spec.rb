require "rails_helper"

RSpec.describe IngestDocumentJob do
  let(:first_paragraph) { Array.new(100) { "anxiety" }.join(" ") }
  let(:second_paragraph) { Array.new(100) { "therapy" }.join(" ") }
  let(:document) { create(:document, title: "Dr. Example", body: "#{first_paragraph}\n\n#{second_paragraph}") }

  it "splits the body into ordered chunks and stores an embedding for each" do
    stub_embeddings

    described_class.perform_now(document)

    chunks = document.chunks.reload
    expect(chunks.map(&:content)).to eq([ first_paragraph, second_paragraph ])
    expect(chunks.map(&:position)).to eq([ 0, 1 ])
    expect(chunks.map { |chunk| chunk.embedding.to_a }).to eq([ axis_vector(0), axis_vector(1) ])
  end

  it "embeds every chunk in a single call, prefixed with the document title" do
    embedded = stub_embeddings

    described_class.perform_now(document)

    expect(RubyLLM).to have_received(:embed).once
    expect(embedded).to eq([ "Dr. Example\n\n#{first_paragraph}", "Dr. Example\n\n#{second_paragraph}" ])
  end

  it "replaces the chunks from a previous ingestion" do
    stub_embeddings
    stale = create(:chunk, document: document, position: 0, content: "stale")
    other_document_chunk = create(:chunk)

    described_class.perform_now(document)

    expect(Chunk.exists?(stale.id)).to be(false)
    expect(document.chunks.reload.map(&:content)).to eq([ first_paragraph, second_paragraph ])
    expect(Chunk.exists?(other_document_chunk.id)).to be(true)
  end

  it "clears the chunks of an emptied document without calling the embeddings API" do
    stub_embeddings
    document.update!(body: "")
    create(:chunk, document: document)

    described_class.perform_now(document)

    expect(document.chunks.reload).to be_empty
    expect(RubyLLM).not_to have_received(:embed)
  end

  it "keeps the existing chunks when embedding fails" do
    existing = create(:chunk, document: document, position: 0)
    allow(RubyLLM).to receive(:embed).and_raise(RubyLLM::ConfigurationError, "OpenAI provider is not configured")

    expect { described_class.perform_now(document) }.to raise_error(RubyLLM::ConfigurationError)
    expect(document.chunks.reload).to eq([ existing ])
  end
end
