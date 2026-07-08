# frozen_string_literal: true

require "open3"

module Railbow
  # Runs git commands defensively: when the git binary is not installed,
  # returns empty output and a failed status instead of raising Errno::ENOENT.
  module GitUtils
    MISSING_GIT_STATUS = Object.new

    def MISSING_GIT_STATUS.success?
      false
    end

    module_function

    def capture2(*args)
      Open3.capture2("git", *args)
    rescue Errno::ENOENT
      ["", MISSING_GIT_STATUS]
    end

    def capture3(*args)
      Open3.capture3("git", *args)
    rescue Errno::ENOENT
      ["", "", MISSING_GIT_STATUS]
    end
  end
end
