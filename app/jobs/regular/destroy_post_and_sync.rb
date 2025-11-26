# frozen_string_literal: true

module ::Jobs
  class DestroyPostAndSync < ::Jobs::Base
    def execute(args)
      post_type = args[:post_type]
      post_number = args[:post_number]
      post_id = args[:post_id]
      operation = args[:operation]
      topic_slug = args[:topic_slug]
      topic_id = args[:topic_id]
      category_id = args[:category_id]

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
        
    end
  end
end
