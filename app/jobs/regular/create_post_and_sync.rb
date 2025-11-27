# frozen_string_literal: true

require 'base64'
require 'faraday'
require 'json'

module ::Jobs
  class CreatePostAndSync < ::Jobs::Base
    def execute(args)
      post_type = args[:post_type]
      operation = args[:operation]

      target_repo = SiteSetting.target_github_repo
      repo_user = target_repo.split("https://github.com/")[1].split("/")[0]
      repo_name = target_repo.split("https://github.com/")[1].split("/")[1]

      if (SiteSetting.disallowed_categories.to_s.split("|").include? args[:category_id].to_s) && (!SiteSetting.disallowed_categories.empty?) then
        return
      end

      conn = Faraday.new(
        url: "https://api.github.com",
        headers: {
          "Accept" => "application/vnd.github+json",
          "Authorization" => "Bearer #{SiteSetting.github_access_token}",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )
      
      username = User.find_by(id: args[:user_id]).username
      topic_id = args[:topic_id]
      
      category_name = ""
      category_slug = ""

      # For edited topic posts
      if !args[:category_id] then
        topic_category_id = Topic.find_by(id: topic_id).category_id.to_i
        category_name = Category.find_by(id: topic_category_id).name
        category_slug = Category.find_by(id: topic_category_id).slug
      else
        if post_type == "topic" && Category.find_by(id: args[:category_id]) then
          category_name = Category.find_by(id: args[:category_id]).name
          category_slug = Category.find_by(id: args[:category_id]).slug
        else
         category_name = "Nil"
         category_slug = "Nil"
        end
      end

      # Exclude PMs
      if Topic.find_by(id: topic_id).archetype == "private_message" then
        return
      end
      
      topic_name = "undefined"
      topic_slug = "undefined"
      if Topic.find_by(id: topic_id) then
        topic_name = Topic.find_by(id: topic_id).title
        topic_slug = Topic.find_by(id: topic_id).slug
      end

      created_at = args[:created_at]
      updated_at = args[:updated_at]

      post_number = args[:post_number]
      post_id = args[:post_id]
      whisper = args[:whisper]
      
      cooked = args[:cooked]
      content = ""

      if post_type == "topic" then
        content = SiteSetting.topic_post_template
      else
        content = SiteSetting.reply_post_template
      end

      if content.include? "@{post_type}" then
        content = content.sub(
          "@{post_type}",
          post_type
        )
      end
      if content.include? "@{topic_name}" then
        content = content.sub(
          "@{topic_name}",
          '"' + topic_name.to_s + '"'
        )
      end
      if content.include? "@{topic_id}" then
        content = content.sub(
          "@{topic_id}",
          topic_id.to_s
        )
      end
      if content.include? "@{category_name}" then
        content = content.sub(
          "@{category_name}",
          category_name
        )
      end
      if content.include? "@{created_at}" then
        content = content.sub(
          "@{created_at}",
          created_at
        )
      end
      if content.include? "@{updated_at}" then
        content = content.sub(
          "@{updated_at}",
          updated_at
        )
      end
      if content.include? "@{whisper}" then
        content = content.sub(
          "@{whisper}",
          whisper.to_s
        )
      end
      if content.include? "@{username}" then
        content = content.sub(
          "@{username}",
          username
        )
      end
      if content.include? "@{post_content}" then
        content = content.sub(
          "@{post_content}",
          cooked.to_s
        )
      end

      content_encoded = Base64.encode64(content) # Github needs text in Base64

      file_path = post_type == "topic" ? SiteSetting.topic_post_path : SiteSetting.reply_post_path.sub("@{post_number}", post_number.to_s)
      if file_path.include? "@{category_slug}" then
        file_path = file_path.sub("@{category_slug}", category_slug)
      end

      if file_path.include? "@{topic_slug}" then
        file_path = file_path.sub("@{topic_slug}", topic_slug)
      end

      # Check if file exists
      existing = conn.get("/repos/#{repo_user}/#{repo_name}/contents/#{file_path}")

      if existing.status == 200 then
        operation = "update"
      end

      if operation == "update" then
        Jobs.enqueue(
          :destroy_post_and_sync,
          post_type: post_type,
          post_id: post_id
        )
      end

      sha = nil
      if operation == "update" then
        resp = conn.get("/repos/#{repo_user}/#{repo_name}/contents/#{file_path}")
        if resp.status == 200 then          
          body = JSON.parse(resp.body)
          if body["sha"] then
            sha = body["sha"]
          else
            operation = "create"
          end
        else
          operation = "create"
        end
      end

      req_body = {}
      if operation == "create" then
        req_body = {
          message: SiteSetting.commit_message,
          committer: {
            "name": SiteSetting.github_committer_username,
            "email": SiteSetting.github_committer_email
          },
          content: content_encoded,
        }
      else
        req_body = {
          message: SiteSetting.commit_message,
          committer: {
            "name": SiteSetting.github_committer_username,
            "email": SiteSetting.github_committer_email
          },
          sha: sha,
          content: content_encoded,
        }
      end

      json_req_body = JSON.generate(req_body)
      
      resp = conn.put(
        "/repos/#{repo_user}/#{repo_name}/contents/#{file_path}",
        json_req_body
      )

      if (resp.status == 200) || (resp.status == 201) then
        if SiteSetting.log_when_post_uploaded then
          Rails.logger.info "Topic '#{topic_name}' has been #{operation == "create" ? "uploaded" : "updated"}"
        end
      elsif (resp.status == 422) || (resp.status == 403) then # Job failed
        Rails.logger.error "An error occurred when trying to upload or update '#{topic_name}': #{resp.body}"
        if resp.headers["x-ratelimit-remaining"].to_i == 0 then # Rate limit reached
          time_reset = Time.at(resp.headers["x-ratelimit-remaining"].to_i)
          time_now = Time.now()
          time_until_reset = time_reset - time_now # In seconds
          wait_before_retry_min = 60 # 60 seconds
          wait_before_retry = [time_until_reset, wait_before_retry_min].max
          Jobs.enqueue_in(wait_before_retry, :create_post_and_sync, args)
        end
      else # Other issues
        # Retry job
        Jobs.enqueue_in(60, :create_post_and_sync, args) # Wait 60 seconds
      end
    end
  end
end
