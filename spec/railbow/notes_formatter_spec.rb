# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "railbow/notes_formatter"
require "support/status_fixture"

RSpec.describe Railbow::NotesFormatter do
  include StatusFixture

  let(:formatter) { Object.new.extend(described_class) }

  describe "#blame_file" do
    it "dates every line of an untracked file as uncommitted, without leaking git stderr" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "untracked.js")
        File.write(path, "// TODO: make this a vec3\n")

        blame = nil
        expect { blame = formatter.send(:blame_file, path) }.not_to output.to_stderr_from_any_process

        expect(blame.dig(1, :date)).to eq(Railbow::Clock.in_zone(Time.now).to_date)
        expect(blame.dig(1, :author)).to eq("Not Committed Yet")
      end
    end

    it "returns no blame for a missing file" do
      expect(formatter.send(:blame_file, "does/not/exist.rb")).to eq({})
    end
  end

  describe "#railbow_display" do
    it "fills the author column with dashes for uncommitted notes instead of formatting git's placeholder as a name" do
      allow(Railbow::Params).to receive_messages(git_author: "all", since: "all", sort: "file", help?: false)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "untracked.js")
        File.write(path, "// TODO: make this a vec3\n")
        annotation = Struct.new(:line, :tag, :text).new(1, "TODO", "make this a vec3")

        out = capture_stdout { formatter.send(:railbow_display, {path => [annotation]}) }

        expect(out).to include("----")
        expect(out).not_to include("No Y")
      end
    end
  end
end
