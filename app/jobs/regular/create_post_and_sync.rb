# frozen_string_literal: true

require 'base64'
require 'faraday'
require 'json'

module ::Jobs
  class CreatePostAndSync < ::Jobs::Base
    def execute(args)
      post_type = args[:post_type]
      username = User.find_by(id: args[:user_id]).username
      category_name = post_type == "topic" ? Category.find_by(id: args[:category_id]).name : nil

      topic_id = post_type == "topic" ? args[:id] : args[:topic_id]
      topic_name = Topic.find_by(id: topic_id).name
      cooked = args[:cooked]
      cooked_encoded = Base64.encode64(cooked) # Github needs text in Base64
      created_at = args[:created_at]
      updated_at = args[:updated_at]
      whisper = args[:whisper]

      file_path = post_type == "topic" ? SiteSetting.topic_post_path : SiteSetting.reply_post_path
      file_path.sub!("@{category}", category_name)
      file_path.sub!("@{topic_name}", topic_name)

      conn = Faraday.new(
        url: "http://api.github.com",
        headers: {
          "Accept" => "application/vnd.github+json",
          "Authorization" => SiteSetting.github_access_token,
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )

      req_body = {
        :message => cooked_encoded,
        
      }

      resp = conn.put("/repos/#{SiteSetting.github_committer_username}/#{SiteSetting.github_repo_name}/contents/#{file_path}", 
    end
  end
end
