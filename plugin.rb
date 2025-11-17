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
    Jobs.enqueue(
      :create_post_and_sync,
      post_type: "topic",
      post: topic
    )
  end

  on(:post_created) do |post|
    Jobs.enqueue(
      :create_post_and_sync,
      post_type: "post",
      post: post
    )
  end

  on(:topic_destroyed) do |topic|
    Jobs.enqueue(
      :destroy_post_and_sync,
      post_type: "topic",
      post: topic
    )
  end

  on(:post_destroyed) do |post|
    Jobs.enqueue(
      :destroy_post_and_sync,
      post_type: "post",
      post: post
    )
  end
end
