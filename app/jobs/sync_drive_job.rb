# Mirrors the clinic's Google Drive folder into Documents. Scheduled hourly in
# config/recurring.yml.
class SyncDriveJob < ApplicationJob
  queue_as :default

  def perform
    unless Sources::GoogleDrive.configured?
      Rails.logger.info("[SyncDriveJob] Google Drive is not configured; skipping sync")
      return
    end

    Sources::Sync.new(Sources::GoogleDrive.new).call
  end
end
