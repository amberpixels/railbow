# frozen_string_literal: true

require "spec_helper"
require "railbow/git_utils"

RSpec.describe Railbow::GitUtils do
  describe ".capture2" do
    it "returns output and status from git" do
      output, status = described_class.capture2("rev-parse", "--is-inside-work-tree")
      expect(output.strip).to eq("true")
      expect(status.success?).to be(true)
    end

    it "returns empty output and a failed status when git is not installed" do
      allow(Open3).to receive(:capture2).and_raise(Errno::ENOENT)
      output, status = described_class.capture2("status")
      expect(output).to eq("")
      expect(status.success?).to be(false)
    end
  end

  describe ".capture3" do
    it "returns empty output and a failed status when git is not installed" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
      output, stderr, status = described_class.capture3("status")
      expect(output).to eq("")
      expect(stderr).to eq("")
      expect(status.success?).to be(false)
    end
  end
end
