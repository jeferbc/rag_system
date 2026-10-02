module Admin
  class DocumentsController < BaseController
    MAX_FAILURES_SHOWN = 5

    def index
      @documents = Document.left_joins(:chunks)
                           .select("documents.*, COUNT(chunks.id) AS chunks_count")
                           .group("documents.id")
                           .order(:category, :title)
    end

    def create
      files = Array(params[:files]).grep(ActionDispatch::Http::UploadedFile)
      return redirect_to(admin_documents_path, alert: "Choose at least one file.", status: :see_other) if files.empty?

      results = files.map do |file|
        DocumentUpload.import(file, category: params[:category], psychologist_ref: params[:psychologist_ref])
      end

      redirect_to admin_documents_path, status: :see_other,
                                        notice: summary(results), alert: failures(results)
    end

    def destroy
      document = Document.find(params[:id])
      document.destroy!

      redirect_to admin_documents_path, notice: "Deleted “#{document.title}”.", status: :see_other
    end

    private

    def summary(results)
      counts = results.map(&:status).tally
      labels = { created: "added", updated: "updated", unchanged: "unchanged" }

      labels.filter_map { |status, label| "#{counts[status]} #{label}" if counts[status] }.to_sentence.presence
    end

    # Kept short: the flash lives in the session cookie.
    def failures(results)
      failed = results.select { |result| result.status == :failed }
      return if failed.empty?

      shown = failed.first(MAX_FAILURES_SHOWN).map { |result| "#{result.filename.truncate(60)} (#{result.message.truncate(100)})" }
      shown << "and #{failed.size - MAX_FAILURES_SHOWN} more" if failed.size > MAX_FAILURES_SHOWN
      "Not imported: #{shown.join('; ')}"
    end
  end
end
