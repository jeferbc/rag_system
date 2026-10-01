# Stubs the Google Drive REST API at the HTTP level with WebMock, so the real
# API client runs against a fake folder tree and never touches the network.
module DriveHelpers
  DRIVE_API = "https://www.googleapis.com/drive/v3"
  ROOT_FOLDER_ID = "root-folder"

  # A Drive client with no credentials; every request it makes is stubbed.
  def drive_source(folder_id: ROOT_FOLDER_ID)
    Sources::GoogleDrive.new(folder_id: folder_id, service: Google::Apis::DriveV3::DriveService.new)
  end

  def drive_folder(id, name)
    drive_file(id, name, Sources::GoogleDrive::FOLDER)
  end

  def drive_doc(id, name, modified: "2026-01-01T10:00:00.000Z")
    drive_file(id, name, Sources::GoogleDrive::GOOGLE_DOC, modified: modified)
  end

  def drive_pdf(id, name, modified: "2026-01-01T10:00:00.000Z")
    drive_file(id, name, Sources::GoogleDrive::PDF, modified: modified)
  end

  def drive_file(id, name, mime_type, modified: "2026-01-01T10:00:00.000Z")
    { id: id, name: name, mimeType: mime_type, modifiedTime: modified }
  end

  # Stubs the folder tree, given as { folder_id => [children] }. The root
  # folder must be one of the keys.
  def stub_drive_tree(tree)
    stub_request(:get, "#{DRIVE_API}/files/#{ROOT_FOLDER_ID}")
      .with(query: hash_including("fields" => "id"))
      .to_return(json_response(id: ROOT_FOLDER_ID))

    tree.each { |folder_id, children| stub_drive_listing(folder_id, children) }
  end

  def stub_drive_listing(folder_id, children, page_token: nil, next_page_token: nil)
    query = { "q" => "'#{folder_id}' in parents and trashed = false" }
    query["pageToken"] = page_token if page_token

    stub_request(:get, "#{DRIVE_API}/files")
      .with(query: hash_including(query))
      .to_return(json_response({ files: children, nextPageToken: next_page_token }.compact))
  end

  def stub_drive_export(id, text)
    stub_request(:get, "#{DRIVE_API}/files/#{id}/export")
      .with(query: hash_including("mimeType" => "text/plain"))
      .to_return(status: 200, body: text, headers: { "Content-Type" => "text/plain" })
  end

  def stub_drive_download(id, data)
    stub_request(:get, "#{DRIVE_API}/files/#{id}")
      .with(query: hash_including("alt" => "media"))
      .to_return(status: 200, body: data, headers: { "Content-Type" => "application/pdf" })
  end

  def json_response(payload)
    { status: 200, body: payload.to_json, headers: { "Content-Type" => "application/json" } }
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

RSpec.configure { |config| config.include DriveHelpers }
