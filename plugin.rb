# frozen_string_literal: true

# name: discourse-static-pages-sync
# about: "Sync topics and posts as static pages to a Github repository"
# meta_topic_id: TODO
# version: 0.0.1
# authors: NateDhaliwal
# url: TODO
# required_version: 2.7.0

enabled_site_setting :discourse_static_pages_sync_enabled

module ::DiscourseStaticPagesSync
  PLUGIN_NAME = "discourse-static-pages-sync"
end

require_relative "lib/discourse_static_pages_sync/engine"

after_initialize do
  # Topic.register_custom_field_type('topic_synced', :boolean)
  # # Post.register_custom_field_type('post_synced', :boolean)

  # register_topic_custom_field_type('topic_synced', :boolean)
  # # register_post_custom_field_type('post_synced', :boolean)

  # add_to_class(:topic, :boolean) do
  #   if !custom_fields['topic_synced'].nil?
  #     custom_fields['topic_synced']
  #   else
  #     nil
  #   end
  # end

  # add_to_class(:topic, "topic_synced=") do |value|
  #   custom_fields['topic_synced'] = value
  # end

  # add_preloaded_topic_list_custom_field('topic_synced')
  
  %w[
    ../app/jobs/scheduled/backfill_sync_topics.rb
    ../app/jobs/regular/create_post_and_sync.rb
    ../app/jobs/regular/destroy_post_and_sync.rb
    ../app/models/discourse_static_pages_sync/synced_topics_backfill.rb
  ].each { |path| require File.expand_path(path, __FILE__) }
  
  on(:topic_created) do |topic|
    # topic.send(
    #   "topic_synced=".to_sym,
    #   false,
    # )
    # topic.save!

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
  end

  on(:post_created) do |post|
    post_type = post[:post_type]
    if post.post_number > 1 && (post_type == 1 || post_type == 2) then # Exclude topic posts and private messages 
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

  # This will be for topics and posts
  # We will check if the post_number is 1, if it is, it is the OP
  on(:post_edited) do |post|
    post_type = post[:post_type]
    if post_type == 1 || post_type == 2 then # Exclude topic posts and private messages 
      Jobs.enqueue(
        :create_post_and_sync,
        post_type: post[:post_number] == 1 ? "topic" : "post",
        operation: "update",
        user_id: post[:user_id].to_i,
        topic_id: post[:post_number] == 1 ? post[:id].to_i : post[:topic_id].to_i,
        cooked: post[:cooked].to_s,
        created_at: post[:created_at].to_s,
        updated_at: post[:updated_at].to_s,
        whisper: post[:post_type] == 4,
        post_number: post[:post_number].to_i
      )
    end
  end

  on(:topic_destroyed) do |topic|
    Jobs.enqueue(
      :destroy_post_and_sync,
      post_type: "topic",
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

  on(:post_destroyed) do |post|
    Jobs.enqueue(
      :destroy_post_and_sync,
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
