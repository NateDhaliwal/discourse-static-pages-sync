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

      created_at = args[:created_at]
      updated_at = args[:updated_at]
      whisper = args[:whisper]
      
      cooked = args[:cooked]
      content = ""

      if post_type == "topic" then
        content = SiteSetting.topic_post_template.sub(
          "@{post_type}",
          post_type
        ).sub!(
          "@{topic_name}",
          topic_name
        ).sub!(
          "@{topic_id}",
          topic_id
        ).sub!(
          "@{category_name}",
          category_name
        ).sub!(
          "@{created_at}",
          created_at
        ).sub!(
          "@{updated_at}",
          updated_at
        )
        # ).sub!(
        #   "@{whisper}",
        #   whisper
        # )
      else
        content = SiteSetting.reply_post_template.sub(
          "@{post_type}",
          post_type
        ).sub!(
          "@{topic_name}",
          topic_name
        ).sub!(
          "@{topic_id}",
          topic_id
        ).sub!(
          "@{created_at}",
          created_at
        ).sub!(
          "@{updated_at}",
          updated_at
        ).sub!(
          "@{whisper}",
          whisper
        )
      end

      content += "\n\n" + cooked
      content_encoded = Base64.encode64(content) # Github needs text in Base64

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
        :message => SiteSetting.commit_message,
        :committer => {
          "name": SiteSetting.github_committer_username,
          "email": SiteSetting.github_committer_email
        },
        :content => cooked_encoded,
      }

      json_req_body = JSON.generate(req_body)

      target_repo = SiteSetting.target_github_repo
      repo_user = target_repo.split("https://github.com/")[1].split("/")[0]
      repo_name =target_repo.split("https://github.com/")[1].split("/")[1]
      
      resp = conn.put(
        "/repos/#{repo_user}/#{repo_name}/contents/#{file_path}",
        json_req_body
      )

      if (resp.status == 200 or resp.status == 201) and SiteSetting.log_when_post_synced then
        Rails.logger.info "Topic '#{topic_name}' has been uploaded"
      elsif resp.status == 422 or resp.status == 403 then # Job failed
        Rails.logger.error "An error occurred when trying to upload '#{topic_name}': #{resp.body}"
        if resp.headers["x-ratelimit-remaining"].to_i == 0: # Rate limit reached
          time_reset = Time.at(1659645535)
          time_now = Time.now()
          wait_before_retry_min = 60 # 60 seconds
          wait_before_retry = [time_reset - time_now, wait_before_retry_min].max
          Jobs.enqueue_in(wait_before_retry, :create_post_and_sync, args)
        end
      else # Other issues
        # Retry job
        Jobs.enqueue_in(60, :create_post_and_sync, args) # Wait 60 seconds
      end
    end
  end
end
