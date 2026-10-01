require "rails_helper"

RSpec.describe Sources::GoogleDrive do
  subject(:source) { drive_source }

  describe "#each_entry" do
    it "walks the folder recursively and describes each ingestable file" do
      stub_drive_tree(
        "root-folder" => [ drive_doc("faq", "FAQ - Booking"), drive_folder("psy", "psy-101-ana-torres") ],
        "psy" => [ drive_pdf("bio", "Ana Torres - Bio.pdf", modified: "2026-03-04T05:06:07.890Z") ]
      )

      entries = source.each_entry.to_a

      expect(entries.map(&:source_id)).to eq(%w[faq bio])
      expect(entries.last).to have_attributes(
        title: "Ana Torres - Bio",
        category: "psychologist",
        psychologist_ref: "psy-101-ana-torres",
        modified_at: Time.utc(2026, 3, 4, 5, 6, 7.89r),
        content_type: "application/pdf"
      )
    end

    it "uses the psy-<id>-<slug> folder name as psychologist_ref, including for nested folders" do
      stub_drive_tree(
        "root-folder" => [ drive_folder("psy-a", "psy-101-ana-torres"), drive_folder("psy-b", "psy-A7-ben-okafor") ],
        "psy-a" => [ drive_doc("a-bio", "Bio"), drive_folder("a-extra", "Publications") ],
        "a-extra" => [ drive_doc("a-paper", "Paper") ],
        "psy-b" => [ drive_doc("b-bio", "Bio") ]
      )

      refs = source.each_entry.to_h { |entry| [ entry.source_id, entry.psychologist_ref ] }

      expect(refs).to eq(
        "a-bio" => "psy-101-ana-torres",
        "a-paper" => "psy-101-ana-torres",
        "b-bio" => "psy-A7-ben-okafor"
      )
    end

    it "leaves psychologist_ref empty for root files and for folders that do not match the pattern" do
      stub_drive_tree(
        "root-folder" => [ drive_doc("faq", "FAQ - Booking"), drive_doc("policy", "Cancellation Policy"),
                           drive_doc("about", "About the clinic"), drive_folder("misc", "psychology-articles") ],
        "misc" => [ drive_doc("article", "Sleep hygiene") ]
      )

      entries = source.each_entry.to_a

      expect(entries.map(&:psychologist_ref)).to all(be_nil)
      expect(entries.to_h { |entry| [ entry.source_id, entry.category ] }).to eq(
        "faq" => "faq", "policy" => "policy", "about" => "general", "article" => "general"
      )
    end

    it "skips unsupported file types and logs a warning for each" do
      stub_drive_tree(
        "root-folder" => [
          drive_doc("doc", "FAQ"),
          drive_file("sheet", "Price list", "application/vnd.google-apps.spreadsheet"),
          drive_file("scan", "Leaflet.jpg", "image/jpeg")
        ]
      )
      allow(Rails.logger).to receive(:warn)

      entries = source.each_entry.to_a

      expect(entries.map(&:source_id)).to eq([ "doc" ])
      expect(Rails.logger).to have_received(:warn).with(/Skipping "Price list" \(sheet\): unsupported type .*spreadsheet/)
      expect(Rails.logger).to have_received(:warn).with(%r{Skipping "Leaflet.jpg" \(scan\): unsupported type image/jpeg})
    end

    it "follows pagination" do
      stub_drive_tree({})
      stub_drive_listing("root-folder", [ drive_doc("one", "One") ], next_page_token: "page-2")
      stub_drive_listing("root-folder", [ drive_doc("two", "Two") ], page_token: "page-2")

      expect(source.each_entry.map(&:source_id)).to eq(%w[one two])
    end

    it "only lists files that are not in the trash" do
      stub_drive_tree("root-folder" => [])

      source.each_entry.to_a

      expect(a_request(:get, "#{DriveHelpers::DRIVE_API}/files")
        .with(query: hash_including("q" => "'root-folder' in parents and trashed = false"))).to have_been_made.once
    end

    it "raises instead of yielding nothing when the root folder is not accessible" do
      stub_request(:get, "#{DriveHelpers::DRIVE_API}/files/root-folder")
        .with(query: hash_including({}))
        .to_return(status: 404, body: { error: { code: 404, message: "File not found" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { source.each_entry.to_a }.to raise_error(Google::Apis::ClientError)
    end
  end

  describe "#fetch_body" do
    def entry(id, content_type)
      Sources::Entry.new(source_id: id, title: "T", category: "faq", psychologist_ref: nil,
                         modified_at: Time.utc(2026, 1, 1), content_type: content_type)
    end

    it "exports a Google Doc as plain text" do
      stub_drive_export("doc", "﻿Opening hours\r\n\r\nMonday to Friday, 8am to 7pm.\r\n")

      body = source.fetch_body(entry("doc", described_class::GOOGLE_DOC))

      expect(body).to eq("Opening hours\n\nMonday to Friday, 8am to 7pm.")
      expect(body.encoding).to eq(Encoding::UTF_8)
    end

    it "downloads a PDF and extracts its text" do
      stub_drive_download("pdf", minimal_pdf("Sessions last 50 minutes."))

      expect(source.fetch_body(entry("pdf", described_class::PDF))).to eq("Sessions last 50 minutes.")
    end

    it "raises a FetchError for a PDF that cannot be parsed" do
      stub_drive_download("pdf", "this is not a pdf")

      expect { source.fetch_body(entry("pdf", described_class::PDF)) }.to raise_error(Sources::FetchError)
    end

    it "raises a FetchError when Drive refuses the export" do
      stub_request(:get, "#{DriveHelpers::DRIVE_API}/files/doc/export")
        .with(query: hash_including({}))
        .to_return(status: 403, body: { error: { code: 403, message: "Export too large" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { source.fetch_body(entry("doc", described_class::GOOGLE_DOC)) }.to raise_error(Sources::FetchError)
    end
  end

  describe "configuration" do
    it "reads the folder ID from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_DRIVE_FOLDER_ID").and_return("folder-from-env")

      expect(described_class.folder_id).to eq("folder-from-env")
    end

    it "is not configured without a folder ID and service account" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_DRIVE_FOLDER_ID").and_return(nil)

      expect(described_class).not_to be_configured
    end

    it "refuses to build a source without a folder ID" do
      expect { described_class.new(folder_id: nil) }.to raise_error(Sources::Error, /folder ID/)
    end
  end
end
