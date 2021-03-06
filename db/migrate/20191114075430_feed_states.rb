class FeedStates < ActiveRecord::Migration
  def change
    create_table :feed_states do |t|
      t.references :feed, null: false
      t.integer :feed_version_id
      t.datetime :last_fetched_at
      t.datetime :last_successful_fetch_at
      t.string :last_fetch_error, null: false, default: ""
      t.boolean :feed_realtime_enabled, null: false, default: false
      t.integer :feed_priority
      t.st_polygon :geometry, geographic: true
      t.json :tags
      t.timestamps null: false
    end
    add_foreign_key :feed_states, :current_feeds, column: :feed_id
    add_foreign_key :feed_states, :feed_versions, column: :feed_version_id
    add_index :feed_states, :feed_id, unique: true
    add_index :feed_states, :feed_version_id, unique: true
    add_index :feed_states, :feed_priority, unique: true

    add_foreign_key :feed_versions, :current_feeds, column: :feed_id

    add_column :current_feeds, :file, :string, null: false, default: ""
    add_column :old_feeds, :file, :string

  end
end
