# frozen_string_literal: true

module ::Jobs
  class DestroyPostAndSync < ::Jobs::Base
    def execute(args)
      post_type = args[:post_type]
      post_id = args[:post_id]
      
      post_edits = JSON.parse(faraday.get("/posts/#{post_id}/revisions/latest.json").body)
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
  end
end
