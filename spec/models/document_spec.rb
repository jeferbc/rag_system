require "rails_helper"

RSpec.describe Document do
  it "requires source_id to be unique within a source" do
    create(:document, source: "google_drive", source_id: "abc")

    expect(build(:document, source: "google_drive", source_id: "abc")).not_to be_valid
    expect(build(:document, source: "seed", source_id: "abc")).to be_valid
  end

  it "returns chunks in position order" do
    document = create(:document)
    second = create(:chunk, document: document, position: 1)
    first = create(:chunk, document: document, position: 0)

    expect(document.chunks).to eq([ first, second ])
  end

  it "removes its chunks when destroyed" do
    document = create(:document)
    create(:chunk, document: document)

    expect { document.destroy }.to change(Chunk, :count).by(-1)
  end
end
