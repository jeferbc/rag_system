require "pdf-reader"

# Turns an uploaded file into plain text. PDFs go through pdf-reader; text and
# Markdown files are read as they are.
class TextExtractor
  class Error < StandardError; end

  EXTENSIONS = %w[.pdf .txt .md].freeze

  def self.extract(filename, data)
    text =
      case File.extname(filename).downcase
      when ".pdf" then pdf_text(data)
      when ".txt", ".md" then utf8(data)
      else raise Error, "unsupported file type (use #{EXTENSIONS.join(', ')})"
      end

    # Postgres rejects NUL bytes in text columns.
    text = text.delete("\u0000").gsub(/\r\n?/, "\n").strip
    raise Error, "no text found (scanned PDFs need OCR, which is not supported yet)" if text.empty?

    text
  end

  def self.pdf_text(data)
    PDF::Reader.new(StringIO.new(data)).pages.map(&:text).join("\n\n")
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => error
    raise Error, "could not read the PDF (#{error.message})"
  end

  # Files saved by older Windows editors are often Windows-1252, not UTF-8.
  def self.utf8(data)
    text = data.dup.force_encoding(Encoding::UTF_8)
    unless text.valid_encoding?
      text = data.dup.force_encoding(Encoding::WINDOWS_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    text.delete_prefix("﻿")
  end

  private_class_method :pdf_text, :utf8
end
