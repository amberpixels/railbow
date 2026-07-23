# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railbow do
  describe ".plain?" do
    env_keys = %w[RBW_PLAIN RBW_FORCE NO_COLOR CLAUDECODE CI]

    around do |example|
      saved = env_keys.to_h { |k| [k, ENV[k]] }
      env_keys.each { |k| ENV.delete(k) }
      example.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "is false on a tty with no env overrides" do
      expect(described_class.plain?).to be(false)
    end

    it "is true when output is not a tty" do
      allow($stdout).to receive(:tty?).and_return(false)
      expect(described_class.plain?).to be(true)
    end

    %w[NO_COLOR CLAUDECODE CI].each do |key|
      it "is true when #{key} is set" do
        ENV[key] = "1"
        expect(described_class.plain?).to be(true)
      end

      it "is false when #{key} is set but RBW_FORCE=1" do
        ENV[key] = "1"
        ENV["RBW_FORCE"] = "1"
        expect(described_class.plain?).to be(false)
      end
    end

    it "is false with RBW_FORCE=1 when output is not a tty" do
      allow($stdout).to receive(:tty?).and_return(false)
      ENV["RBW_FORCE"] = "1"
      expect(described_class.plain?).to be(false)
    end

    it "is true when RBW_PLAIN=1, even with RBW_FORCE=1" do
      ENV["RBW_PLAIN"] = "1"
      ENV["RBW_FORCE"] = "1"
      expect(described_class.plain?).to be(true)
    end

    it "treats RBW_PLAIN=0 as unset and falls through to heuristics" do
      ENV["RBW_PLAIN"] = "0"
      ENV["CLAUDECODE"] = "1"
      expect(described_class.plain?).to be(true)
    end

    it "treats RBW_FORCE=0 as unset" do
      ENV["RBW_FORCE"] = "0"
      ENV["CI"] = "1"
      expect(described_class.plain?).to be(true)
    end
  end
end
