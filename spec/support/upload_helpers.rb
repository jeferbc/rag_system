# Builds in-memory uploads for specs, including a real (tiny) PDF.
module UploadHelpers
  def uploaded_file(filename, content, content_type = "text/plain")
    Rack::Test::UploadedFile.new(StringIO.new(content), content_type, original_filename: filename)
  end

  def uploaded_pdf(filename, text)
    uploaded_file(filename, minimal_pdf(text), "application/pdf")
  end

  # A valid single-page PDF containing +text+, built by hand so the suite
  # needs neither a binary fixture nor a PDF-writing gem.
  def minimal_pdf(text)
    stream = "BT /F1 12 Tf 72 720 Td (#{text.gsub(/[()\\]/) { |char| "\\#{char}" }}) Tj ET"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R " \
        "/Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]

    pdf = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |object, index|
      pdf.bytesize.tap { pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n" }
    end
    xref_offset = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
  end
end

RSpec.configure { |config| config.include UploadHelpers }
