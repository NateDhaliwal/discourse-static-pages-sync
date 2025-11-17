module DiscourseStaticPagesSync
  class DestroyPost < ::Jobs::Regular
    def execute(args)
      post_type = args[:post_type]
      author = args[:post][:author][:username]
      id = post_type == "topic" ? args[:post][:id] : args[:post][:topic_id]
    end
  end
end
