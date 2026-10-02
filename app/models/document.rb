# A piece of static clinic content (psychologist bio, FAQ, policy). Its body
# is split into embedded Chunks for retrieval.
class Document < ApplicationRecord
  CATEGORIES = %w[psychologist faq policy general].freeze

  has_many :chunks, -> { order(:position) }, dependent: :delete_all

  validates :title, :source, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :source_id, presence: true, uniqueness: { scope: :source }

  scope :from_source, ->(source) { where(source: source) }
end
