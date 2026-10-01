# Loads the synthetic knowledge base of the fictional "Calma Therapy Center"
# (db/seeds/knowledge_base.yml). Idempotent, and needs neither Google Drive
# credentials nor an LLM API key: documents are stored without embeddings.
# Run `bin/rails documents:ingest` afterwards to chunk and embed them.

seed_source = "seed"

entries = YAML.load_file(Rails.root.join("db/seeds/knowledge_base.yml"), symbolize_names: true)

entries.each do |entry|
  document = Document.find_or_initialize_by(source: seed_source, source_id: entry.fetch(:id))
  document.assign_attributes(
    title: entry.fetch(:title),
    category: entry.fetch(:category),
    psychologist_ref: entry[:psychologist_ref],
    body: entry.fetch(:body).strip
  )
  next unless document.changed?

  # Chunks of an edited document are stale; dropping them marks it for re-ingestion.
  document.chunks.delete_all if document.persisted?
  document.save!
end

Document.from_source(seed_source).where.not(source_id: entries.map { |entry| entry.fetch(:id) }).destroy_all

puts "Seeded #{Document.from_source(seed_source).count} knowledge base documents " \
     "(#{Document.where.missing(:chunks).count} awaiting `bin/rails documents:ingest`)"
