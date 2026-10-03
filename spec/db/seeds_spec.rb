require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def seed
    silence_stream { load Rails.root.join("db/seeds.rb") }
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  it "loads the fictional clinic's knowledge base without credentials or network access" do
    seed

    expect(Document.pluck(:source).uniq).to eq([ "seed" ])
    expect(Document.group(:category).count).to eq("psychologist" => 12, "faq" => 12, "policy" => 6)
    expect(Document.where(category: "psychologist").pluck(:psychologist_ref)).to all(match(/\Apsy-\d+-[a-z-]+\z/))
    expect(Document.where.not(category: "psychologist").pluck(:psychologist_ref)).to all(be_nil)
    expect(Chunk.count).to eq(0)
  end

  it "is idempotent and does not enqueue embedding jobs" do
    seed

    expect { seed }.not_to change { Document.order(:id).pluck(:id, :updated_at) }
    expect(enqueued_jobs).to be_empty
  end

  it "drops the chunks of a seed document whose content changed, and leaves other sources alone" do
    seed
    edited = Document.find_by!(source_id: "policy-payment")
    edited.update!(body: "Outdated text.")
    create(:chunk, document: edited)
    uploaded_document = create(:document, source: "upload")

    seed

    expect(edited.reload.body).to start_with("El pago se realiza el mismo día de cada sesión.")
    expect(edited.chunks).to be_empty
    expect(Document.exists?(uploaded_document.id)).to be(true)
  end

  # Prices and availability are live data served by tools; they must never be embedded.
  it "contains no prices" do
    seed

    expect(Document.pluck(:body)).to all(satisfy { |body| body !~ /[$€£]|\b(USD|EUR|COP|dollars?|euros?|pesos?|dólares)\b/i })
  end
end
