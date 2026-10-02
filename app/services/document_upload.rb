# Imports one uploaded file as a Document and queues its ingestion.
#
# The filename identifies the document: uploading a file with the same name
# again replaces the earlier version instead of creating a duplicate.
class DocumentUpload
  SOURCE = "upload"
  MAX_BYTES = 10.megabytes

  Result = Data.define(:filename, :status, :message)

  def self.import(file, category:, psychologist_ref: nil)
    filename = File.basename(file.original_filename.to_s)
    raise TextExtractor::Error, "file is larger than #{MAX_BYTES / 1.megabyte} MB" if file.size > MAX_BYTES

    document = Document.find_or_initialize_by(source: SOURCE, source_id: filename)
    status = document.new_record? ? :created : :updated
    document.assign_attributes(
      title: File.basename(filename, ".*"),
      category: category,
      psychologist_ref: psychologist_ref.presence,
      body: TextExtractor.extract(filename, file.read)
    )

    # An identical re-upload is a no-op, unless an earlier ingestion never
    # finished (e.g. the embeddings API was down): then it is retried.
    return Result.new(filename, :unchanged, nil) if !document.changed? && document.chunks.exists?

    document.source_modified_at = Time.current if document.changed?
    document.save!
    IngestDocumentJob.perform_later(document)
    Result.new(filename, status, nil)
  rescue TextExtractor::Error => error
    Result.new(filename, :failed, error.message)
  rescue ActiveRecord::RecordInvalid => error
    Result.new(filename, :failed, error.record.errors.full_messages.to_sentence)
  end
end
