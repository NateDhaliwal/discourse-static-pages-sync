# frozen_string_literal: true

class ::Jobs::BackfillSyncTopics < ::Jobs::Scheduled
  every 24.hours
    
  def execute(args)
    last_synced = DiscourseStaticPagesSync::SyncedTopicsBackfill.first

    # Check if backfill job has been ran before
    if last_synced then
      if last_synced != 1 then # Not synced to first topic
        last_synced_id = last_synced.topic_id
        sync_start = last_synced_id - SiteSetting.backfill_sync_topics_count
        sync_end = last_synced_id

        topics_to_sync = Topic.where("id > ? AND id < ?", sync_start, sync_end)

        topics_to_sync.each do |topic|
          Jobs.enqueue(
            :create_post_and_sync,
            post_type: "topic",
            operation: "create",
            title: topic[:title],
            topic_id: topic[:id],
            user_id: topic[:user_id],
            category_id: topic[:category_id],
            cooked: topic[:cooked],
            created_at: topic[:created_at],
            updated_at: topic[:updated_at],
            whisper: topic[:post_type] == 4,
            post_number: topic[:post_number]
          )

          topic.ordered_posts.each do |post|
            if post.post_number > 1 then
              Jobs.enqueue(
                :create_post_and_sync,
                post_type: "post",
                operation: "create",
                user_id: post[:user_id],
                topic_id: post[:topic_id],
                cooked: post[:cooked],
                created_at: post[:created_at],
                updated_at: post[:updated_at],
                whisper: post[:post_type] == 4,
                post_number: post[:post_number]
              )
            end
          end
        end

        # Update last_synced
        last_synced.update(topic_id: sync_start)
      end
    else
      # Create last_synced
      last_synced_new = DiscourseStaticPagesSync::SyncedTopicsBackfill.create(topic_id: Topic.last.id) # Most recent topic

      last_synced_id = last_synced_new.topic_id
      # Start the backfill
      sync_start = last_synced_id - SiteSetting.backfill_sync_topics_count
      sync_end = last_synced_id

      topics_to_sync = Topic.where("id > ? AND id < ?", sync_start, sync_end)

      topics_to_sync.each do |topic|
        Jobs.enqueue(
          :create_post_and_sync,
          post_type: "topic",
          operation: "create",
          title: topic[:title],
          topic_id: topic[:id],
          user_id: topic[:user_id],
          category_id: topic[:category_id],
          cooked: topic[:cooked],
          created_at: topic[:created_at],
          updated_at: topic[:updated_at],
          whisper: topic[:post_type] == 4,
          post_number: topic[:post_number]
        )

        topic.ordered_posts.each do |post|
          if post.post_number > 1 then
            Jobs.enqueue(
              :create_post_and_sync,
              post_type: "post",
              operation: "create",
              user_id: post[:user_id],
              topic_id: post[:topic_id],
              cooked: post[:cooked],
              created_at: post[:created_at],
              updated_at: post[:updated_at],
              whisper: post[:post_type] == 4,
              post_number: post[:post_number]
            )
          end
        end
      end
      # Update last_synced_new
      last_synced_new.update(topic_id: sync_start)
    end
  end
end
