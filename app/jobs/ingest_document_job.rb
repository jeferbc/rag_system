# Rebuilds a document's chunks: splits the body, embeds every chunk and
# replaces whatever chunks the document had before.
class IngestDocumentJob < ApplicationJob
  EMBED_BATCH_SIZE = 100

  queue_as :default

  # The document was deleted (e.g. removed from the source) before the job ran.
  discard_on ActiveJob::DeserializationError
  retry_on RubyLLM::RateLimitError, RubyLLM::OverloadedError, RubyLLM::ServiceUnavailableError,
           wait: :polynomially_longer, attempts: 5

  def perform(document)
    contents = Chunker.split(document.body)

    # Embed before touching the database so a provider failure leaves the
    # existing chunks in place.
    embeddings = contents.each_slice(EMBED_BATCH_SIZE).flat_map do |batch|
      Chunk.embed(batch.map { |content| embedding_input(document, content) })
    end

    document.with_lock do
      document.chunks.delete_all
      contents.zip(embeddings).each_with_index do |(content, embedding), position|
        document.chunks.create!(content: content, position: position, embedding: embedding)
      end
    end
  end

  private

  # The title travels with every chunk so a fragment like "Sessions are held
  # in English and Spanish" still embeds close to the psychologist it describes.
  def embedding_input(document, content)
    "#{document.title}\n\n#{content}"
  end
end
