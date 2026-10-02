class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.string :category, null: false
      # Where the document came from ("upload", "seed", ...) and its id within
      # that source, so each source only ever manages its own rows.
      t.string :source, null: false
      t.string :source_id, null: false
      t.datetime :source_modified_at
      t.string :psychologist_ref

      t.timestamps
    end

    add_index :documents, [ :source, :source_id ], unique: true
    add_index :documents, :psychologist_ref
  end
end
