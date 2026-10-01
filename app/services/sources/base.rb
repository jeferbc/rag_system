module Sources
  # The contract every content source implements. To add one (Notion, manual
  # uploads, ...) subclass this and run it through Sources::Sync.
  class Base
    # Stable identifier stored in Document#source, e.g. "google_drive".
    def key
      raise NotImplementedError
    end

    # Yields a Sources::Entry for every item currently in the source. Items
    # the source cannot ingest are skipped here. Must raise (rather than yield
    # a partial list) if the source cannot be listed, because documents that
    # are not yielded get deleted.
    def each_entry
      raise NotImplementedError
    end

    # Returns the plain-text body of +entry+. Raises Sources::FetchError when
    # this one item cannot be read.
    def fetch_body(entry)
      raise NotImplementedError
    end
  end
end
