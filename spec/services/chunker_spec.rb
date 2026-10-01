require "rails_helper"

RSpec.describe Chunker do
  def paragraph(length, word: "calm")
    Array.new(length / (word.length + 1)) { word }.join(" ")
  end

  it "returns no chunks for blank text" do
    expect(described_class.split(nil)).to eq([])
    expect(described_class.split(" \n\n \n")).to eq([])
  end

  it "keeps a short text as a single chunk" do
    expect(described_class.split("Our clinic opens at 8am.")).to eq([ "Our clinic opens at 8am." ])
  end

  it "packs consecutive paragraphs into one chunk while they fit" do
    text = "First paragraph.\n\nSecond paragraph.\n\n\n  Third paragraph.  "

    expect(described_class.split(text)).to eq([ "First paragraph.\n\nSecond paragraph.\n\nThird paragraph." ])
  end

  it "starts a new chunk at a paragraph boundary when the limit would be exceeded" do
    first, second, third = paragraph(500, word: "one"), paragraph(500, word: "two"), paragraph(200, word: "six")

    chunks = described_class.split([ first, second, third ].join("\n\n"))

    expect(chunks).to eq([ first, "#{second}\n\n#{third}" ])
  end

  it "treats Windows line endings as paragraph breaks" do
    first, second = paragraph(500), paragraph(500)

    expect(described_class.split("#{first}\r\n\r\n#{second}")).to eq([ first, second ])
  end

  it "breaks an oversized paragraph at sentence boundaries" do
    sentence = "#{paragraph(290)}."
    text = Array.new(5) { sentence }.join(" ")

    chunks = described_class.split(text)

    expect(chunks).to eq([ "#{sentence} #{sentence}", "#{sentence} #{sentence}", sentence ])
  end

  it "never exceeds the limit and never drops content, even without sentence breaks" do
    text = "#{paragraph(2000)} #{'x' * 1000}\n\n#{paragraph(300)}"

    chunks = described_class.split(text)

    expect(chunks.map(&:length)).to all(be <= 800)
    expect(chunks.join.delete(" \n")).to eq(text.delete(" \n"))
  end

  it "honours a custom chunk size" do
    chunks = described_class.split("One two three.\n\nFour five six.", max_chars: 20)

    expect(chunks).to eq([ "One two three.", "Four five six." ])
  end
end
