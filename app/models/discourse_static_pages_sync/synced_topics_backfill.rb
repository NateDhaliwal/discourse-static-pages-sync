# frozen_string_literal: true

module ::DiscourseStaticPagesSync
  class SyncedTopicsBackfill < ActiveRecord::Base
    self.table_name = 'synced_topics_backfill'

    validates :topic_id, presence: true
  end
end

# == Schema Information
#
# Table name: synced_topics_backfill
#
#  id         :bigint           not null, primary key
#  topic_id   :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
