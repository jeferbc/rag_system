class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :document, null: false, foreign_key: true
      t.text :content, null: false
      t.integer :position, null: false
      t.vector :embedding, limit: 1536, null: false

      t.timestamps
    end

    add_index :chunks, [ :document_id, :position ], unique: true
    add_index :chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
