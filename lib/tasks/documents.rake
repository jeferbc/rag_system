namespace :documents do
  desc "Chunk and embed documents that have no chunks yet (ALL=1 redoes every document). Needs OPENAI_API_KEY."
  task ingest: :environment do
    abort "OPENAI_API_KEY is not set; it is required to embed documents." if RubyLLM.config.openai_api_key.blank?

    documents = ENV["ALL"].present? ? Document.all : Document.where.missing(:chunks)
    total = documents.count

    documents.find_each.with_index(1) do |document, index|
      IngestDocumentJob.perform_now(document)
      puts "[#{index}/#{total}] #{document.title} (#{document.chunks.count} chunks)"
    end

    puts "Ingested #{total} documents; #{Chunk.count} chunks in the knowledge base."
  end
end
