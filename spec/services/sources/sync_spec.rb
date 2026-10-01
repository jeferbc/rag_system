require "rails_helper"

RSpec.describe Sources::Sync do
  # An in-memory source: the smallest thing that satisfies Sources::Base.
  let(:fake_source_class) do
    Class.new(Sources::Base) do
      attr_reader :items, :fetched

      def initialize(items)
        @items = items
        @fetched = []
      end

      def key = "fake"

      def each_entry
        items.each do |id, item|
          yield Sources::Entry.new(source_id: id, title: item[:title], category: "faq", content_type: "text/plain",
                                   psychologist_ref: item[:psychologist_ref], modified_at: item[:modified_at])
        end
      end

      def fetch_body(entry)
        fetched << entry.source_id
        items.fetch(entry.source_id).fetch(:body).then { |body| body.is_a?(Exception) ? raise(body) : body }
      end
    end
  end

  let(:monday) { Time.utc(2026, 1, 5, 9) }
  let(:tuesday) { Time.utc(2026, 1, 6, 9) }
  let(:items) { { "a" => { title: "Hours", body: "Open 8 to 7.", modified_at: monday } } }
  let(:source) { fake_source_class.new(items) }

  def sync
    described_class.new(source).call
  end

  it "creates a document for a new entry and enqueues its ingestion" do
    items["a"][:psychologist_ref] = "psy-101-ana-torres"

    expect { sync }.to have_enqueued_job(IngestDocumentJob).once

    expect(Document.sole).to have_attributes(
      source: "fake", source_id: "a", title: "Hours", body: "Open 8 to 7.", category: "faq",
      psychologist_ref: "psy-101-ana-torres", source_modified_at: monday
    )
    expect(IngestDocumentJob).to have_been_enqueued.with(Document.sole)
  end

  it "skips an entry whose modified time has not changed" do
    sync
    source.fetched.clear
    items["a"][:body] = "This edit is invisible because the modified time did not move."

    expect { sync }.not_to have_enqueued_job(IngestDocumentJob)

    expect(source.fetched).to be_empty
    expect(Document.sole.body).to eq("Open 8 to 7.")
    expect(sync).to have_attributes(created: 0, updated: 0, unchanged: 1, deleted: 0)
  end

  it "updates the document and re-enqueues ingestion when the modified time changes" do
    sync
    items["a"].merge!(title: "Opening hours", body: "Open 9 to 6.", modified_at: tuesday)

    expect { sync }.to have_enqueued_job(IngestDocumentJob).with(Document.sole)

    expect(Document.sole).to have_attributes(title: "Opening hours", body: "Open 9 to 6.", source_modified_at: tuesday)
  end

  it "picks up a move between folders even when the modified time is unchanged" do
    sync
    source.fetched.clear
    items["a"][:psychologist_ref] = "psy-202-ben-okafor"

    expect { sync }.to have_enqueued_job(IngestDocumentJob)

    expect(Document.sole.psychologist_ref).to eq("psy-202-ben-okafor")
    expect(source.fetched).to be_empty
  end

  it "destroys documents, and their chunks, that are no longer in the source" do
    items["b"] = { title: "Parking", body: "Free parking.", modified_at: monday }
    sync
    removed = Document.find_by!(source_id: "b")
    create(:chunk, document: removed)
    items.delete("b")

    result = sync

    expect(result.deleted).to eq(1)
    expect(Document.pluck(:source_id)).to eq([ "a" ])
    expect(Chunk.count).to eq(0)
  end

  it "never deletes documents that belong to another source" do
    seeded = create(:document, source: "seed", source_id: "a")
    items.clear

    sync

    expect(Document.all).to eq([ seeded ])
  end

  it "deletes nothing when listing the source fails part-way" do
    items["b"] = { title: "Parking", body: "Free parking.", modified_at: monday }
    sync
    allow(source).to receive(:each_entry).and_yield(
      Sources::Entry.new(source_id: "a", title: "Hours", category: "faq", psychologist_ref: nil,
                         modified_at: monday, content_type: "text/plain")
    ).and_raise(Sources::Error, "listing failed")

    expect { sync }.to raise_error(Sources::Error)
    expect(Document.count).to eq(2)
  end

  it "keeps the stored document when one entry cannot be read, and syncs the rest" do
    sync
    items["a"].merge!(body: Sources::FetchError.new("corrupt PDF"), modified_at: tuesday)
    items["b"] = { title: "Parking", body: "Free parking.", modified_at: monday }
    allow(Rails.logger).to receive(:error)

    result = sync

    expect(result).to have_attributes(failed: 1, created: 1, deleted: 0)
    expect(Document.find_by!(source_id: "a")).to have_attributes(body: "Open 8 to 7.", source_modified_at: monday)
    expect(Rails.logger).to have_received(:error).with(/could not read "Hours" \(a\): corrupt PDF/)
  end
end
