FactoryBot.define do
  factory :document do
    sequence(:title) { |n| "Document #{n}" }
    body { "Calma Therapy Center is a fictional clinic used for test data." }
    category { "faq" }
    source { "google_drive" }
    sequence(:source_id) { |n| "file-#{n}" }
    source_modified_at { Time.utc(2026, 1, 1) }
  end
end
