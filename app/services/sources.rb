# Content sources feed static clinic content (bios, FAQs, policies) into
# Documents. Each source is an adapter with the interface of Sources::Base;
# Sources::Sync mirrors any of them into the database.
module Sources
  class Error < StandardError; end

  # One item could not be read (corrupt PDF, export refused, ...). The sync
  # logs it, keeps the stored document as it is and carries on.
  class FetchError < Error; end

  # Metadata for one item in a source. The body is fetched separately, and
  # only when the item is new or has changed.
  Entry = Data.define(:source_id, :title, :category, :psychologist_ref, :modified_at, :content_type)
end
