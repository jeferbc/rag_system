require "rails_helper"

RSpec.describe "Admin documents" do
  def basic_auth(user, password)
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end

  describe "GET /admin/documents" do
    it "shows the upload form and the documents with their embedding status" do
      embedded = create(:document, title: "Cancellation Policy", category: "policy")
      create(:chunk, document: embedded)
      create(:document, title: "Elena Marsh", category: "psychologist", psychologist_ref: "psy-101-elena-marsh")

      get admin_documents_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('type="file"', 'multiple="multiple"', "2 documents",
                                       "Cancellation Policy", "Elena Marsh", "psy-101-elena-marsh", "Not embedded yet")
    end
  end

  describe "POST /admin/documents" do
    it "imports several files at once and queues each for ingestion" do
      files = [
        uploaded_file("FAQ - Online sessions.txt", "Yes, we offer online sessions."),
        uploaded_pdf("Cancellation.pdf", "Cancel at least 24 hours ahead."),
        uploaded_file("About.md", "# About\n\nA fictional clinic.")
      ]

      expect { post admin_documents_path, params: { files: files, category: "faq" } }
        .to have_enqueued_job(IngestDocumentJob).exactly(3).times

      expect(response).to redirect_to(admin_documents_path)
      expect(Document.order(:title).pluck(:title, :category, :body)).to eq([
        [ "About", "faq", "# About\n\nA fictional clinic." ],
        [ "Cancellation", "faq", "Cancel at least 24 hours ahead." ],
        [ "FAQ - Online sessions", "faq", "Yes, we offer online sessions." ]
      ])
      follow_redirect!
      expect(response.body).to include("3 added")
    end

    it "imports the readable files and reports the ones it could not import" do
      create(:document, source: "upload", source_id: "hours.txt", body: "Open 8 to 7.")
      files = [
        uploaded_file("hours.txt", "Open 9 to 6."),
        uploaded_file("new.txt", "Free parking."),
        uploaded_file("prices.xlsx", "data", "application/vnd.ms-excel")
      ]

      post admin_documents_path, params: { files: files, category: "faq", psychologist_ref: "" }
      follow_redirect!

      expect(Document.pluck(:source_id)).to contain_exactly("hours.txt", "new.txt")
      expect(response.body).to include("1 added and 1 updated", "Not imported: prices.xlsx (unsupported file type")
    end

    it "asks for a file when none was selected" do
      post admin_documents_path, params: { category: "faq" }
      follow_redirect!

      expect(response.body).to include("Choose at least one file.")
      expect(Document.count).to eq(0)
    end
  end

  describe "DELETE /admin/documents/:id" do
    it "deletes the document and its chunks" do
      document = create(:document, title: "Old policy")
      create(:chunk, document: document)

      expect { delete admin_document_path(document) }.to change(Document, :count).by(-1).and change(Chunk, :count).by(-1)

      follow_redirect!
      expect(response.body).to include("Deleted “Old policy”.")
    end
  end

  describe "authentication" do
    context "when ADMIN_PASSWORD is set" do
      before { stub_const("ENV", ENV.to_h.merge("ADMIN_USER" => "clinic", "ADMIN_PASSWORD" => "s3cret")) }

      it "rejects requests without valid credentials" do
        get admin_documents_path
        expect(response).to have_http_status(:unauthorized)

        get admin_documents_path, headers: basic_auth("clinic", "wrong")
        expect(response).to have_http_status(:unauthorized)

        post admin_documents_path, params: { files: [ uploaded_file("a.txt", "text") ], category: "faq" }
        expect(response).to have_http_status(:unauthorized)
        expect(Document.count).to eq(0)
      end

      it "lets the admin in" do
        get admin_documents_path, headers: basic_auth("clinic", "s3cret")

        expect(response).to have_http_status(:ok)
      end
    end

    it "stays locked outside development and test when no password is configured" do
      stub_const("ENV", ENV.to_h.except("ADMIN_PASSWORD"))
      allow(Rails.env).to receive(:local?).and_return(false)

      get admin_documents_path, headers: basic_auth("admin", "")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
