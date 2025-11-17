module ::Jobs
  class DestroyPostAndSync < ::Jobs::Base
    def execute(args)
      post_type = args[:post_type]
      author = args[:post][:author][:username]
      id = post_type == "topic" ? args[:post][:id] : args[:post][:topic_id]
      puts args[:post_type]
      puts args[:post]
    end
  end
end
