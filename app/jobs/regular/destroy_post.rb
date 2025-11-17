module DiscourseStaticPagesSync
  class DestroyPost < ::Jobs::Regular
    def execute(args)
      post_type = args.post_type
      author = args.post.author.username
      id = args.post.id
    end
  end
end
