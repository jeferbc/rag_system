# A piece of static clinic content (psychologist bio, FAQ, policy) pulled from
# a content source. Its body is split into embedded Chunks for retrieval.
class Document < ApplicationRecord
  has_many :chunks, -> { order(:position) }, dependent: :delete_all

  validates :title, :category, :source, presence: true
  validates :source_id, presence: true, uniqueness: { scope: :source }

  scope :from_source, ->(source) { where(source: source) }
end
