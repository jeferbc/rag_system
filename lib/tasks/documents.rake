namespace :documents do
  desc "Chunk and embed documents that have no chunks yet (ALL=1 redoes every document). Needs OPENAI_API_KEY."
  task ingest: :environment do
    provider = RubyLLM.models.find(Chunk::EMBEDDING_MODEL).provider
    if RubyLLM.config.public_send("#{provider}_api_key").blank?
      abort "#{provider.upcase}_API_KEY is not set; #{Chunk::EMBEDDING_MODEL} needs it to embed documents."
    end

    documents = ENV["ALL"].present? ? Document.all : Document.where.missing(:chunks)
    total = documents.count

    documents.find_each.with_index(1) do |document, index|
      IngestDocumentJob.perform_now(document)
      puts "[#{index}/#{total}] #{document.title} (#{document.chunks.count} chunks)"
    end

    puts "Ingested #{total} documents; #{Chunk.count} chunks in the knowledge base."
  end
end
