# frozen_string_literal: true

# name: discourse-static-pages-sync
# about: TODO
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
  %w[
    ../app/jobs/regular/create_post_and_sync.rb
    ../app/jobs/regular/destroy_post_and_sync.rb
  ].each { |path| require File.expand_path(path, __FILE__) }
  
  on(:topic_created) do |topic|
    puts topic[:category_id]
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
      post_number: post[:post_number]
    )
  end

  on(:post_created) do |post|
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

  # This will be for topics and posts
  # We will check if the post_number is 1, if it is, it is the OP
  on(:post_edited) do |post|
    Jobs.enqueue(
      :create_post_and_sync,
      post_type: post[:post_number] == 1 ? "topic" : "post",
      operation: "update",
      user_id: post[:user_id],
      topic_id: post[:post_number] == 1 ? post[:id] : post[:topic_id],
      cooked: post[:cooked],
      created_at: post[:created_at],
      updated_at: post[:updated_at],
      whisper: post[:post_type] == 4
    )
  end

  on(:topic_destroyed) do |topic|
    Jobs.enqueue(
      :destroy_post_and_sync,
      post_type: "topic",
      user_id: topic[:user_id],
      topic_id: topic[:topic_id],
      cooked: topic[:cooked],
      created_at: topic[:created_at],
      updated_at: topic[:updated_at],
      whisper: topic[:post_type] == 4
    )
  end

  on(:post_destroyed) do |post|
    Jobs.enqueue(
      :destroy_post_and_sync,
      post_type: "topic",
      title: post[:title],
      topic_id: post[:id],
      user_id: post[:user_id],
      cooked: post[:cooked],
      created_at: post[:created_at],
      updated_at: post[:updated_at],
      whisper: post[:post_type] == 4
    )
  end
end
