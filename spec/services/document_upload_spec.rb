require "rails_helper"

RSpec.describe DocumentUpload do
  def import(file, category: "faq", psychologist_ref: nil)
    described_class.import(file, category: category, psychologist_ref: psychologist_ref)
  end

  it "creates a document from the file and queues its ingestion" do
    result = nil

    expect { result = import(uploaded_file("Opening hours.txt", "Open 8 to 7."), psychologist_ref: "") }
      .to have_enqueued_job(IngestDocumentJob).once

    expect(result).to have_attributes(filename: "Opening hours.txt", status: :created, message: nil)
    expect(Document.sole).to have_attributes(
      source: "upload", source_id: "Opening hours.txt", title: "Opening hours", category: "faq",
      psychologist_ref: nil, body: "Open 8 to 7."
    )
    expect(IngestDocumentJob).to have_been_enqueued.with(Document.sole)
  end

  it "stores the psychologist reference when given" do
    import(uploaded_pdf("Bio.pdf", "Treats anxiety."), category: "psychologist", psychologist_ref: "psy-101-elena-marsh")

    expect(Document.sole).to have_attributes(category: "psychologist", psychologist_ref: "psy-101-elena-marsh",
                                             body: "Treats anxiety.")
  end

  it "replaces the document when a file with the same name is uploaded again" do
    import(uploaded_file("hours.txt", "Open 8 to 7."))

    result = nil
    expect { result = import(uploaded_file("hours.txt", "Open 9 to 6.")) }.to have_enqueued_job(IngestDocumentJob).once

    expect(result.status).to eq(:updated)
    expect(Document.sole.body).to eq("Open 9 to 6.")
  end

  it "does nothing for an identical re-upload that is already embedded" do
    import(uploaded_file("hours.txt", "Open 8 to 7."))
    create(:chunk, document: Document.sole)

    result = nil
    expect { result = import(uploaded_file("hours.txt", "Open 8 to 7.")) }.not_to have_enqueued_job(IngestDocumentJob)

    expect(result.status).to eq(:unchanged)
  end

  it "retries ingestion for an identical re-upload that was never embedded" do
    import(uploaded_file("hours.txt", "Open 8 to 7."))

    expect { import(uploaded_file("hours.txt", "Open 8 to 7.")) }.to have_enqueued_job(IngestDocumentJob).once
    expect(Document.count).to eq(1)
  end

  it "reports a file it cannot read without creating a document" do
    result = import(uploaded_file("prices.xlsx", "data", "application/vnd.ms-excel"))

    expect(result).to have_attributes(status: :failed, message: /unsupported file type/)
    expect(Document.count).to eq(0)
  end

  it "reports an invalid category" do
    result = import(uploaded_file("hours.txt", "Open 8 to 7."), category: "pricing")

    expect(result).to have_attributes(status: :failed, message: /Category is not included in the list/)
    expect(Document.count).to eq(0)
  end

  it "rejects files over the size limit" do
    stub_const("DocumentUpload::MAX_BYTES", 10)

    expect(import(uploaded_file("hours.txt", "More than ten bytes."))).to have_attributes(status: :failed, message: /larger than/)
  end
end
