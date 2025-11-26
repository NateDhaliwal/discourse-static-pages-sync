# frozen_string_literal: true

module ::Jobs
  class DestroyPostAndSync < ::Jobs::Base
    def get_sha(file_path)
      target_repo = SiteSetting.target_github_repo
      repo_user = target_repo.split("https://github.com/")[1].split("/")[0]
      repo_name = target_repo.split("https://github.com/")[1].split("/")[1]

      conn = Faraday.new(
        url: "https://api.github.com",
        headers: {
          "Accept" => "application/vnd.github+json",
          "Authorization" => "Bearer #{SiteSetting.github_access_token}",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )
      
      sha = nil
      resp = conn.get("/repos/#{repo_user}/#{repo_name}/contents/#{file_path}")
      if resp.status == 200 then          
        body = JSON.parse(resp.body)
        if body["sha"] then
          sha = body["sha"]
        end
      end

      return sha
    end
    
    def execute(args)
      post_type = args[:post_type]
      post_number = args[:post_number]
      post_id = args[:post_id]
      operation = args[:operation]
      topic_slug = args[:topic_slug]
      topic_id = args[:topic_id]
      category_id = args[:category_id]

      target_repo = SiteSetting.target_github_repo
      repo_user = target_repo.split("https://github.com/")[1].split("/")[0]
      repo_name = target_repo.split("https://github.com/")[1].split("/")[1]

      conn = Faraday.new(
        url: "https://api.github.com",
        headers: {
          "Accept" => "application/vnd.github+json",
          "Authorization" => "Bearer #{SiteSetting.github_access_token}",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )
      
      post_edits = JSON.parse(faraday.get("/posts/#{post_id}/revisions/latest.json").body)
      if post_edits.status == 200 && operation == "edit_topic" then
        old_category_slug = category_slug
        if post_edits.category_changes then
          old_category_slug = Category.find_by(id: post_edits.category_changes.previous).slug
        end
        old_file_path = post_type == "topic" ? SiteSetting.topic_post_path : SiteSetting.reply_post_path.sub("@{post_number}", post_number.to_s)
        if old_file_path.include? "@{category_slug}" then
          old_file_path = old_file_path.sub("@{category_slug}", old_category_slug)
        end
        old_topic_title = post_edits.title_changes.side_by_side.split('<div class=\"revision-content\"><div>')[1].split('</div></div><div class=\"revision-content\">')[0].split("</div></div>")[0].sub("<del>", "").sub("</del>", "")
        old_topic_slug = Slug.for(old_topic_title)
        if old_file_path.include? "@{topic_slug}" then
          old_file_path = old_file_path.sub("@{topic_slug}", old_topic_slug)
        end
      end

      if operation == "delete_topic" then
        category_slug = Category.find_by(id: category_id).slug
        file_path = SiteSetting.topic_post_path
        if file_path.include? "@{category_slug}" then
          file_path = file_path.sub("@{category_slug}", category_slug)
        end
        if file_path.include? "@{topic_slug}" then
          file_path = file_path.sub("@{topic_slug}", topic_slug)
        end
        
        req_body = {
          message: SiteSetting.delete_commit_message,
          committer: {
            "name": SiteSetting.github_committer_username,
            "email": SiteSetting.github_committer_email
          },
          sha: get_sha(file_path)
        }

        json_req_body = JSON.generate(req_body)
        resp = conn.delete("/repos/#{repo_user}/#{repo_name}/contents/#{file_path}", json_req_body)

        if resp.status == 200 then
          if SiteSetting.log_when_post_uploaded then
            Rails.logger.info "Topic '#{topic_name}' has been deleted"
          end
        elsif resp.status == 422 then # Job failed
          Rails.logger.error "An error occurred when trying to delete '#{topic_name}': #{resp.body}"
          if resp.headers["x-ratelimit-remaining"].to_i == 0 then # Rate limit reached
            time_reset = Time.at(resp.headers["x-ratelimit-remaining"].to_i)
            time_now = Time.now()
            time_until_reset = time_reset - time_now # In seconds
            wait_before_retry_min = 60 # 60 seconds
            wait_before_retry = [time_until_reset, wait_before_retry_min].max
            Jobs.enqueue_in(wait_before_retry, :delete_post_and_sync, args)
          end
        else # Other issues
          # Retry job
          Jobs.enqueue_in(60, :delete_post_and_sync, args) # Wait 60 seconds
        end

        # TODO: Add logic to delete associated posts
      end
    end
  end
end
