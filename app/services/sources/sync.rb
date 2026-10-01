module Sources
  # Mirrors a content source into Documents: creates and updates what changed,
  # skips what did not, and destroys documents that left the source.
  class Sync
    Result = Data.define(:created, :updated, :unchanged, :failed, :deleted)

    def initialize(source)
      @source = source
    end

    def call
      seen_ids = []
      counts = Hash.new(0)

      source.each_entry do |entry|
        seen_ids << entry.source_id
        counts[sync_entry(entry)] += 1
      end

      # Only reached when the whole source was listed without error.
      stale = Document.from_source(source.key).where.not(source_id: seen_ids)
      counts[:deleted] = stale.destroy_all.size

      Result.new(**Result.members.index_with { |member| counts[member] }).tap do |result|
        Rails.logger.info("[Sources::Sync] #{source.key}: #{result.to_h.map { |name, count| "#{count} #{name}" }.join(', ')}")
      end
    end

    private

    attr_reader :source

    def sync_entry(entry)
      document = Document.find_or_initialize_by(source: source.key, source_id: entry.source_id)
      outcome = document.new_record? ? :created : :updated

      document.assign_attributes(title: entry.title, category: entry.category, psychologist_ref: entry.psychologist_ref)
      if document.source_modified_at != entry.modified_at
        document.assign_attributes(body: source.fetch_body(entry), source_modified_at: entry.modified_at)
      end
      return :unchanged unless document.changed?

      document.save!
      IngestDocumentJob.perform_later(document)
      outcome
    rescue FetchError => error
      Rails.logger.error("[Sources::Sync] #{source.key}: could not read #{entry.title.inspect} (#{entry.source_id}): #{error.message}")
      :failed
    end
  end
end
