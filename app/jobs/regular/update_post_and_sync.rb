# frozen_string_literal: true

module ::Jobs
  class UpdatePostAndSync < ::Jobs::Base
    def execute(args)
      post_type = args[:post_type]
      username = User.find_by(id: args[:user_id]).username
      puts username
      puts args
    end
  end
end
