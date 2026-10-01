require "google/apis/drive_v3"
require "googleauth"
require "pdf-reader"

module Sources
  # Reads clinic content from a Google Drive folder with a read-only service
  # account. Google Docs and PDFs are ingested; anything else is skipped.
  #
  # Files inside a folder named "psy-<production_id>-<slug>" (at any depth)
  # belong to that psychologist; the folder name becomes their psychologist_ref.
  class GoogleDrive < Base
    KEY = "google_drive"
    FOLDER = "application/vnd.google-apps.folder"
    GOOGLE_DOC = "application/vnd.google-apps.document"
    PDF = "application/pdf"
    PSYCHOLOGIST_FOLDER = /\Apsy-[^-]+-.+\z/
    PAGE_SIZE = 200

    def self.folder_id
      ENV["GOOGLE_DRIVE_FOLDER_ID"].presence || Rails.application.credentials.dig(:google_drive, :folder_id)
    end

    # The service-account key, kept in Rails credentials either as a nested
    # hash or as the raw JSON string downloaded from Google Cloud.
    def self.service_account_json
      key = Rails.application.credentials.dig(:google_drive, :service_account)
      key.is_a?(String) ? key.presence : key&.to_json
    end

    def self.configured?
      folder_id.present? && service_account_json.present?
    end

    def initialize(folder_id: self.class.folder_id, service: nil)
      raise Error, "Google Drive folder ID is not configured" if folder_id.blank?

      @folder_id = folder_id
      @service = service
    end

    def key
      KEY
    end

    def each_entry(&block)
      return enum_for(:each_entry) unless block

      # Listing a folder the service account cannot see returns an empty page
      # rather than an error, which a sync would read as "everything was
      # deleted". Fetching the folder itself fails loudly instead.
      service.get_file(folder_id, fields: "id", supports_all_drives: true)
      walk(folder_id, nil, &block)
    end

    def fetch_body(entry)
      text = entry.content_type == GOOGLE_DOC ? export_google_doc(entry) : extract_pdf(entry)
      text.delete_prefix("﻿").gsub(/\r\n?/, "\n").strip
    rescue Google::Apis::ClientError, ::PDF::Reader::MalformedPDFError, ::PDF::Reader::UnsupportedFeatureError => error
      raise FetchError, "#{error.class}: #{error.message}"
    end

    private

    attr_reader :folder_id

    def walk(folder_id, psychologist_ref, &block)
      each_child(folder_id) do |file|
        case file.mime_type
        when FOLDER
          walk(file.id, file.name[PSYCHOLOGIST_FOLDER] || psychologist_ref, &block)
        when GOOGLE_DOC, PDF
          yield entry_for(file, psychologist_ref)
        else
          Rails.logger.warn("[Sources::GoogleDrive] Skipping #{file.name.inspect} (#{file.id}): unsupported type #{file.mime_type}")
        end
      end
    end

    def each_child(folder_id, &block)
      page_token = nil
      loop do
        page = service.list_files(
          q: "'#{folder_id}' in parents and trashed = false",
          fields: "nextPageToken, files(id, name, mimeType, modifiedTime)",
          order_by: "name",
          page_size: PAGE_SIZE,
          page_token: page_token,
          supports_all_drives: true,
          include_items_from_all_drives: true
        )
        Array(page.files).each(&block)
        page_token = page.next_page_token
        break if page_token.blank?
      end
    end

    def entry_for(file, psychologist_ref)
      Entry.new(
        source_id: file.id,
        title: file.name.delete_suffix(".pdf"),
        category: category_for(file.name, psychologist_ref),
        psychologist_ref: psychologist_ref,
        modified_at: file.modified_time.to_time.utc,
        content_type: file.mime_type
      )
    end

    def category_for(name, psychologist_ref)
      return "psychologist" if psychologist_ref

      case name
      when /faq/i then "faq"
      when /polic/i then "policy"
      else "general"
      end
    end

    def export_google_doc(entry)
      download { |io| service.export_file(entry.source_id, "text/plain", download_dest: io) }.force_encoding(Encoding::UTF_8)
    end

    def extract_pdf(entry)
      data = download { |io| service.get_file(entry.source_id, download_dest: io, supports_all_drives: true) }
      ::PDF::Reader.new(StringIO.new(data)).pages.map(&:text).join("\n\n")
    end

    def download
      StringIO.new("".b).tap { |io| yield io }.string
    end

    def service
      @service ||= Google::Apis::DriveV3::DriveService.new.tap do |drive|
        json = self.class.service_account_json
        raise Error, "Google Drive service account is not configured" if json.blank?

        drive.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(json),
          scope: Google::Apis::DriveV3::AUTH_DRIVE_READONLY
        )
      end
    end
  end
end
