require "rails_helper"

RSpec.describe SyncDriveJob do
  before do
    allow(Sources::GoogleDrive).to receive(:configured?).and_return(true)
    allow(Sources::GoogleDrive).to receive(:new).and_return(drive_source)
  end

  def stub_clinic_drive(faq_modified: "2026-01-01T10:00:00.000Z", with_policy: true)
    root = [
      drive_doc("faq", "FAQ - Online sessions", modified: faq_modified),
      drive_folder("psy", "psy-101-ana-torres"),
      drive_file("prices", "Price list", "application/vnd.google-apps.spreadsheet")
    ]
    root << drive_pdf("policy", "Cancellation Policy.pdf") if with_policy

    stub_drive_tree("root-folder" => root, "psy" => [ drive_doc("bio", "Ana Torres") ])
    stub_drive_export("faq", "Yes, we offer online sessions.")
    stub_drive_export("bio", "Ana Torres treats anxiety. Sessions in English and Spanish.")
    stub_drive_download("policy", minimal_pdf("Cancel at least 24 hours ahead."))
  end

  it "imports Google Docs and PDFs from Drive and enqueues their ingestion" do
    stub_clinic_drive

    expect { described_class.perform_now }.to have_enqueued_job(IngestDocumentJob).exactly(3).times

    expect(Document.order(:source_id).map { |d| [ d.source_id, d.title, d.category, d.psychologist_ref, d.body ] }).to eq([
      [ "bio", "Ana Torres", "psychologist", "psy-101-ana-torres", "Ana Torres treats anxiety. Sessions in English and Spanish." ],
      [ "faq", "FAQ - Online sessions", "faq", nil, "Yes, we offer online sessions." ],
      [ "policy", "Cancellation Policy", "policy", nil, "Cancel at least 24 hours ahead." ]
    ])
    expect(Document.pluck(:source).uniq).to eq([ "google_drive" ])
  end

  it "downloads nothing and enqueues nothing on a second run with no changes" do
    stub_clinic_drive
    described_class.perform_now
    WebMock.reset_executed_requests!

    expect { described_class.perform_now }.not_to have_enqueued_job(IngestDocumentJob)

    expect(a_request(:get, %r{/files/[^/?]+/export})).not_to have_been_made
    expect(a_request(:get, %r{/files/[^/?]+\?.*alt=media})).not_to have_been_made
  end

  it "re-imports only the file whose modifiedTime changed" do
    stub_clinic_drive
    described_class.perform_now
    stub_clinic_drive(faq_modified: "2026-02-01T10:00:00.000Z")
    stub_drive_export("faq", "Yes, online sessions are available by video call.")
    WebMock.reset_executed_requests!

    expect { described_class.perform_now }
      .to have_enqueued_job(IngestDocumentJob).once.with(Document.find_by!(source_id: "faq"))

    expect(Document.find_by!(source_id: "faq").body).to eq("Yes, online sessions are available by video call.")
    expect(a_request(:get, %r{/files/bio/export})).not_to have_been_made
  end

  it "destroys documents for files removed from Drive, along with their chunks" do
    stub_clinic_drive
    described_class.perform_now
    create(:chunk, document: Document.find_by!(source_id: "policy"))
    stub_clinic_drive(with_policy: false)

    expect { described_class.perform_now }.to change(Chunk, :count).by(-1)

    expect(Document.pluck(:source_id)).to contain_exactly("faq", "bio")
  end

  it "does nothing when Drive is not configured" do
    allow(Sources::GoogleDrive).to receive(:configured?).and_return(false)

    expect { described_class.perform_now }.not_to change(Document, :count)
    expect(Sources::GoogleDrive).not_to have_received(:new)
  end
end
