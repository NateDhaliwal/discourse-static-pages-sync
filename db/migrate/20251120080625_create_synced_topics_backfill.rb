# frozen_string_literal: true
class CreateSyncedTopicsBackfill < ActiveRecord::Migration[8.0]
  def change
    create_table :synced_topics_backfill do |t|
      t.integer :topic_id

      t.timestamps
    end
  end
end
