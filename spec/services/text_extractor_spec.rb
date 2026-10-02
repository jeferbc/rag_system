require "rails_helper"

RSpec.describe TextExtractor do
  it "extracts the text of a PDF" do
    expect(described_class.extract("policy.pdf", minimal_pdf("Sessions last 50 minutes."))).to eq("Sessions last 50 minutes.")
  end

  it "reads text and Markdown files as UTF-8, normalising line endings" do
    data = "﻿Horario de atención\r\n\r\nLunes a viernes.\r\n".b

    text = described_class.extract("FAQ.TXT", data)

    expect(text).to eq("Horario de atención\n\nLunes a viernes.")
    expect(text.encoding).to eq(Encoding::UTF_8)
    expect(described_class.extract("notes.md", "# Title")).to eq("# Title")
  end

  it "converts Windows-1252 text instead of mangling accents" do
    data = "Atención psicológica".encode(Encoding::WINDOWS_1252).b

    expect(described_class.extract("faq.txt", data)).to eq("Atención psicológica")
  end

  it "rejects unsupported file types" do
    expect { described_class.extract("prices.xlsx", "data") }
      .to raise_error(TextExtractor::Error, /unsupported file type/)
  end

  it "rejects a file that is not really a PDF" do
    expect { described_class.extract("broken.pdf", "this is not a pdf") }
      .to raise_error(TextExtractor::Error, /could not read the PDF/)
  end

  it "rejects files with no text" do
    expect { described_class.extract("empty.txt", " \n\n") }.to raise_error(TextExtractor::Error, /no text found/)
  end
end
