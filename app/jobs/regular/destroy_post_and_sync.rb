# frozen_string_literal: true
require 'json'
require 'base64'
require 'faraday'

module ::Jobs
  class DestroyPostAndSync < ::Jobs::Base    
    def execute(args)
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
        
        sha = nil # Automatically returned, no need for 'return sha' at the bottom
        resp = conn.get("/repos/#{repo_user}/#{repo_name}/contents/#{file_path}")
        if resp.status == 200 then          
          body = JSON.parse(resp.body)
          if body["sha"] then
            sha = body["sha"]
          end
        end
      end
  
      def delete_file(file_path, sha_arg=nil)
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
        
        req_body = {
          message: SiteSetting.delete_commit_message,
          committer: {
            "name": SiteSetting.github_committer_username,
            "email": SiteSetting.github_committer_email
          },
          sha: sha_arg || get_sha(file_path)
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
      end

      
      post_type = args[:post_type]
      puts "a: " + post_type.to_s
      post_number = args[:post_number]
      puts "b: " + post_number.to_s
      post_id = args[:post_id]
      puts "c: " + post_id.to_s
      operation = args[:operation]
      puts "d: " + operation.to_s
      topic_id = args[:topic_id]
      puts "e: " + topic_id.to_s
      topic_slug = args[:topic_slug] || Topic.find_by(id: topic_id).slug.to_s
      puts "f: " + topic_slug.to_s
      puts "g: " + args[:category_id].to_s
      puts "h: " + Topic.find_by(id: topic_id).title.to_s
      puts "i: " + Topic.find_by(id: topic_id).category_id.to_s
      category_id = args[:category_id] || Topic.find_by(id: topic_id).category_id.to_i
      category_slug = Category.find_by(id: category_id).slug

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
      
      post_edits = JSON.parse(Faraday.get("#{Discourse.base_url}/posts/#{post_id}/revisions/latest.json").body)
      puts post_edits
      puts post_edits["title_changes"]
      
      if !post_edits["errors"] && operation == "edit_topic" then
        old_category_slug = category_slug
        if post_edits["category_changes"] then
          old_category_slug = Category.find_by(id: post_edits["category_changes"]["previous"]).slug
        end
        old_file_path = post_type == "topic" ? SiteSetting.topic_post_path : SiteSetting.reply_post_path.sub("@{post_number}", post_number.to_s)
        if old_file_path.include? "@{category_slug}" then
          old_file_path = old_file_path.sub("@{category_slug}", old_category_slug)
        end

        # In case it does not exist
        return if !post_edits["title_changes"]["side_by_side"]
        
        old_topic_title = post_edits["title_changes"]["side_by_side"]
          &.split('<div class=\"revision-content\"><div>')[1]
          &.split('</div></div><div class=\"revision-content\">')[0]
          &.split("</div></div>")[0]
          &.sub("<del>", "")
          &.sub("</del>", "")
        # Discourse's in-built Slug
        old_topic_slug = Slug.for(old_topic_title)
        if old_file_path.include? "@{topic_slug}" then
          old_file_path = old_file_path.sub("@{topic_slug}", old_topic_slug)
        end

        puts "Old fp:" + old_file_path

        delete_file(old_file_path)

        # Create new topic file here
        Jobs.enqueue(
          :create_post_and_sync,
          post_type: "topic",
          operation: "create",
          title: Topic.find_by(id: topic_id).title.to_s,
          topic_id: topic_id,
          user_id: Topic.find_by(id: topic_id).user_id.to_i,
          category_id: category_id.to_i,
          cooked: Topic.find_by(id: topic_id).ordered_posts[0].cooked.to_s,
          created_at: Topic.find_by(id: topic_id).created_at.to_s,
          updated_at: Topic.find_by(id: topic_id).updated_at.to_s,
          whisper: Topic.find_by(id: topic_id).ordered_posts[0].post_type == 4,
          post_number: 1,
          post_id: post_id.to_i
        )
        # Move replies if slug/category changed (in case SiteSetting.reply_post_path contains @{category_slug})
        if old_topic_slug != topic_slug || old_category_slug != category_slug then
          # Delete replies
          replies_file_path = SiteSetting.reply_post_path
          if replies_file_path.include? "@{category_slug}" then
            replies_file_path = replies_file_path.sub("@{category_slug}", category_slug)
          end
          if replies_file_path.include? "@{topic_slug}" then
            replies_file_path = replies_file_path.sub("@{topic_slug}", topic_slug)
          end
          # We don't replace post_number because that will be appended later on
          if replies_file_path.include? "@{post_number}" then
            replies_file_path = replies_file_path.slice("@{post_number}")
          end
          # TODO: Maybe allow different file extensions?
          replies_file_path = replies_file_path.slice(".md") # Remove '.md.' from the back
          
          synced_replies_list = JSON.parse(conn.get("/repos/#{repo_user}/#{repo_name}/contents/#{replies_file_path}").body)
          synced_replies_list.each do |reply_file|
            # Format: https://api.github.com/repos/NateDhaliwal/ENDPOINT-discourse-static-pages-sync/contents/site-feedback
            reply_file_path = replies_file_path + reply_file.name.to_s
            reply_file_sha = reply_file.sha.to_s
            delete_file(reply_file_path, reply_file_sha)
          end

          # Add new posts
          Topic.find_by(id: topic_id).ordered_posts.each do |post|
            post_type = post[:post_type]
            if post.post_number > 1 && (post_type == 1 || post_type == 2) then
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
                post_number: post[:post_number].to_i,
                post_id: post[:id].to_i
              )
            end
          end
        end
      end

      if operation == "delete_post" then
        file_path = SiteSetting.reply_post_path
        if file_path.include? "@{category_slug}" then
          file_path = file_path.sub("@{category_slug}", category_slug)
        end
        if file_path.include? "@{topic_slug}" then
          file_path = file_path.sub("@{topic_slug}", topic_slug)
        end

        puts "fp: " + file_path

        delete_file(file_path)
      end

      if operation == "delete_topic" then
        file_path = ""
        if !args[:file_path] then
          file_path = SiteSetting.topic_post_path
          if file_path.include? "@{category_slug}" then
            file_path = file_path.sub("@{category_slug}", category_slug)
          end
          if file_path.include? "@{topic_slug}" then
            file_path = file_path.sub("@{topic_slug}", topic_slug)
          end
          if file_path.include? "@{post_number}" then
            file_path = file_path.sub("@{post_number}", post_number)
          end
        else
          file_path = args[:file_path]
        end

        puts "fp: " + file_path
        
        delete_file(file_path)

        # Delete replies
        replies_file_path = SiteSetting.reply_post_path
        if replies_file_path.include? "@{category_slug}" then
          replies_file_path = replies_file_path.sub("@{category_slug}", category_slug)
        end
        if replies_file_path.include? "@{topic_slug}" then
          replies_file_path = replies_file_path.sub("@{topic_slug}", topic_slug)
        end
        # We don't replace post_number because that will be appended later on
        if replies_file_path.include? "@{post_number}" then
          replies_file_path = replies_file_path.slice("@{post_number}")
        end
        # TODO: Maybe allow different file extensions?
        replies_file_path = replies_file_path.slice(".md") # Remove '.md.' from the back
        
        synced_replies_list = JSON.parse(conn.get("/repos/#{repo_user}/#{repo_name}/contents/#{replies_file_path}").body)
        synced_replies_list.each do |reply_file|
          # Format: https://api.github.com/repos/NateDhaliwal/ENDPOINT-discourse-static-pages-sync/contents/site-feedback
          reply_file_path = replies_file_path + reply_file.name.to_s
          reply_file_sha = reply_file.sha.to_s
          delete_file(reply_file_path, reply_file_sha)
        end
      end
    end
  end
end
