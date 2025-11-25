# frozen_string_literal: true

class ::Jobs::BackfillSyncTopics < ::Jobs::Scheduled
  every 10.seconds
    
  def execute(args)
    puts "Running"
    last_synced = DiscourseStaticPagesSync::SyncedTopicsBackfill.first

    return if last_synced&.topic_id == 1

    # Check if backfill job has been ran before
    if last_synced then
      if last_synced.topic_id != 1 then # Not synced to first topic
        last_synced_id = last_synced.topic_id
        sync_start = last_synced_id - SiteSetting.backfill_sync_topics_count <= 1 ? 1 : last_synced_id - SiteSetting.backfill_sync_topics_count
        sync_end = last_synced_id

        puts last_synced_id
        puts sync_start
        puts sync_end

        topics_to_sync = Topic.where("id >= ? AND id <= ?", sync_start, sync_end)

        topics_to_sync.each do |topic|
          puts "Queuing #{topic[:title].to_s}"
          Jobs.enqueue(
            :create_post_and_sync,
            post_type: "topic",
            operation: "create",
            title: topic[:title].to_s,
            topic_id: topic[:id].to_i,
            user_id: topic[:user_id].to_i,
            category_id: topic[:category_id].to_i,
            cooked: topic.ordered_posts[0].cooked.to_s,
            created_at: topic[:created_at].to_s,
            updated_at: topic[:updated_at].to_s,
            whisper: topic[:post_type] == 4,
            post_number: topic[:post_number].to_i
          )

          topic.ordered_posts.each do |post|
            if post.post_number > 1 then
              Jobs.enqueue(
                :create_post_and_sync,
                post_type: "post",
                operation: "create",
                user_id: post[:user_id].to_i,
                topic_id: post[:topic_id].to_i,
                cooked: post[:cooked].to_s,
                created_at: post[:created_at].to_s,
                updated_at: post[:updated_at].to_s,
                whisper: post[:post_type] == 4,
                post_number: post[:post_number].to_i
              )
            end
          end
        end

        # Update last_synced
        last_synced.update!(topic_id: sync_start)
      end
    else
      puts "Create new"
      # Create last_synced
      last_synced_new = DiscourseStaticPagesSync::SyncedTopicsBackfill.create!(topic_id: Topic.last.id) # Most recent topic

      last_synced_id = last_synced_new.topic_id
      # Start the backfill
      sync_start = last_synced_id - SiteSetting.backfill_sync_topics_count <= 1 ? 1 : last_synced_id - SiteSetting.backfill_sync_topics_count
      sync_end = last_synced_id

      puts last_synced_id
      puts sync_start
      puts sync_end

      topics_to_sync = Topic.where("id > ? AND id < ?", sync_start, sync_end)

      topics_to_sync.each do |topic|
        puts "Queuing #{topic[:title].to_s}"
        Jobs.enqueue(
          :create_post_and_sync,
          post_type: "topic",
          operation: "create",
          title: topic[:title].to_s,
          topic_id: topic[:id].to_i,
          user_id: topic[:user_id].to_i,
          category_id: topic[:category_id].to_i,
          cooked: topic.ordered_posts[0].cooked.to_s,
          created_at: topic[:created_at].to_s,
          updated_at: topic[:updated_at].to_s,
          whisper: topic[:post_type] == 4,
          post_number: topic[:post_number].to_i
        )

        topic.ordered_posts.each do |post|
          if post.post_number > 1 then
            Jobs.enqueue(
              :create_post_and_sync,
              post_type: "post",
              operation: "create",
              user_id: post[:user_id].to_i,
              topic_id: post[:topic_id].to_i,
              cooked: post[:cooked].to_s,
              created_at: post[:created_at].to_s,
              updated_at: post[:updated_at].to_s,
              whisper: post[:post_type] == 4,
              post_number: post[:post_number].to_i
            )
          end
        end
      end
      # Update last_synced_new
      last_synced_new.update!(topic_id: sync_start)
    end
  end
end
