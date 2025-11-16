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
  # Code which should run after Rails has finished booting
end
