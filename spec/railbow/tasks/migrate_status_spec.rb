# frozen_string_literal: true

require "spec_helper"
require "active_record"

load File.expand_path("../../../lib/railbow/tasks/migrate_status.rake", __dir__)

RSpec.describe Railbow::MigrateStatusFormatter do
  subject(:helper) { Class.new { include Railbow::MigrateStatusFormatter }.new }

  describe "#apply_branch_mask" do
    it "extracts the first capture group of the mask" do
      expect(helper.send(:apply_branch_mask, "PS-123/add-index", "(PS-[^/]+)/")).to eq("PS-123")
    end

    it "returns the branch unchanged when the mask is empty" do
      expect(helper.send(:apply_branch_mask, "feature/foo", "")).to eq("feature/foo")
    end

    it "returns the branch unchanged when the mask does not match" do
      expect(helper.send(:apply_branch_mask, "feature/foo", "(PS-[^/]+)/")).to eq("feature/foo")
    end

    it "returns the branch unchanged when the mask is an invalid regex" do
      expect(helper.send(:apply_branch_mask, "feature/foo", "([")).to eq("feature/foo")
    end
  end
end
