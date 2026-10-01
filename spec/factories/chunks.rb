FactoryBot.define do
  factory :chunk do
    document
    sequence(:position) { |n| n }
    content { "A paragraph of clinic content." }
    embedding { Array.new(Chunk::EMBEDDING_DIMENSIONS, 0.0).tap { |vector| vector[0] = 1.0 } }
  end
end
