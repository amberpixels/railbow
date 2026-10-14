# frozen_string_literal: true

require "spec_helper"
require "railbow/status/git_data"

RSpec.describe Railbow::Status::GitData do
  describe ".apply_branch_mask" do
    it "extracts the first capture group of the mask" do
      expect(described_class.apply_branch_mask("PS-123/add-index", "(PS-[^/]+)/")).to eq("PS-123")
    end

    it "returns the branch unchanged when the mask is empty" do
      expect(described_class.apply_branch_mask("feature/foo", "")).to eq("feature/foo")
    end

    it "returns the branch unchanged when the mask does not match" do
      expect(described_class.apply_branch_mask("feature/foo", "(PS-[^/]+)/")).to eq("feature/foo")
    end

    it "returns the branch unchanged when the mask is an invalid regex" do
      expect(described_class.apply_branch_mask("feature/foo", "([")).to eq("feature/foo")
    end

    it "extracts a ticket id in auto mode" do
      expect(described_class.apply_branch_mask("feat/PS-1184-thing", "auto")).to eq("PS-1184")
    end
  end

  describe "without a migrations directory" do
    subject(:git) { described_class.new(migrate_dir: nil, author_enabled: false, diff_enabled: true) }

    it "makes no file-scoped git calls and stays empty" do
      expect(Railbow::GitUtils).not_to receive(:capture2)
      expect(Railbow::GitUtils).not_to receive(:capture3)

      expect(git.landed_dates).to be_empty
      expect(git.author_names).to be_empty
      expect(git.branch_origins).to be_empty
      expect(git.uncommitted_files).to be_empty
      expect(git.git_email).to be_nil
    end
  end

  describe "author and landed-date parsing" do
    let(:ok) { instance_double(Process::Status, success?: true) }

    def stub_log(author_output: "", landed_output: "")
      allow(Railbow::GitUtils).to receive(:capture2) do |*args|
        case args
        in ["config", "user.email"] then ["me@example.test\n", ok]
        in ["config", "user.name"] then ["Me\n", ok]
        in ["log", "--first-parent", *] then [landed_output, ok]
        in ["log", *] then [author_output, ok]
        else ["", ok]
        end
      end
    end

    subject(:git) do
      described_class.new(migrate_dir: "db/migrate", author_enabled: true, diff_enabled: false)
    end

    it "maps each migration basename to the author who added it" do
      stub_log(author_output: <<~LOG)
        COMMIT:Ann Apple\tann@example.test
        A\tdb/migrate/20260101000001_add_apples.rb
        COMMIT:Bo Banana\tBO@example.test
        A\tdb/migrate/20260101000002_add_bananas.rb
      LOG

      expect(git.author_names).to eq(
        "20260101000001_add_apples.rb" => "Ann Apple",
        "20260101000002_add_bananas.rb" => "Bo Banana"
      )
      expect(git.author_emails["20260101000002_add_bananas.rb"]).to eq("bo@example.test")
    end

    it "attributes a rename to its destination filename" do
      stub_log(author_output: <<~LOG)
        COMMIT:Ann Apple\tann@example.test
        R100\tdb/migrate/20260101000001_old.rb\tdb/migrate/20260101000001_new.rb
      LOG

      expect(git.author_names.keys).to eq(["20260101000001_new.rb"])
    end

    it "keeps the first author seen for a file, since git log runs newest first" do
      stub_log(author_output: <<~LOG)
        COMMIT:Newer Author\tnewer@example.test
        A\tdb/migrate/20260101000001_add_apples.rb
        COMMIT:Original Author\toriginal@example.test
        A\tdb/migrate/20260101000001_add_apples.rb
      LOG

      expect(git.author_names["20260101000001_add_apples.rb"]).to eq("Newer Author")
    end

    it "parses landed dates from the first-parent log" do
      stub_log(landed_output: <<~LOG)
        COMMIT:2026-03-04T10:00:00+00:00
        A\tdb/migrate/20260210183902_create_pet_tags.rb
      LOG

      expect(git.landed_dates["20260210183902_create_pet_tags.rb"]).to eq(Date.new(2026, 3, 4))
    end

    it "skips a commit whose date will not parse" do
      stub_log(landed_output: <<~LOG)
        COMMIT:not-a-date
        A\tdb/migrate/20260210183902_create_pet_tags.rb
      LOG

      expect(git.landed_dates).to be_empty
    end
  end

  describe "branch origins" do
    let(:ok) { instance_double(Process::Status, success?: true) }
    let(:failed) { instance_double(Process::Status, success?: false) }
    let(:path) { "db/migrate/20260301120000_add_cherries.rb" }
    let(:plain_sha) { "" }
    let(:merge_shas) { "" }
    let(:branch_queries) { [] }

    # The plain log finds the commit that added a file; the -m form also sees
    # files whose current name first appears inside a merge commit.
    before do
      allow(Railbow::GitUtils).to receive(:capture2) do |*args|
        case args
        in ["symbolic-ref", *] then ["refs/remotes/origin/main\n", ok]
        in ["merge-base", "HEAD", "main"] then ["base000\n", ok]
        in ["diff", "--name-status", *] then ["A\t#{path}\n", ok]
        in ["log", "--diff-filter=AR", "--format=%H", "-1", "--", ^(path)] then [plain_sha, ok]
        in ["log", "--diff-filter=AR", "--format=%H", "-m", "--", ^(path)] then [merge_shas, ok]
        in ["branch", "--contains", String => sha, *]
          branch_queries << sha
          ["feature/PS-7\n", ok]
        in ["rev-parse", "--abbrev-ref", "HEAD"] then ["feature/PS-7\n", ok]
        in ["status", "--porcelain", *] then ["", ok]
        else ["", failed]
        end
      end
      allow(Railbow::GitUtils).to receive(:capture3).and_return(["", "", failed])
    end

    subject(:git) do
      described_class.new(migrate_dir: "db/migrate", author_enabled: false, diff_enabled: true)
    end

    context "when the filename was created in a merge commit" do
      let(:merge_shas) { "newer00\nolder00\n" }

      it "falls back to a merge-aware log and attributes the oldest match" do
        expect(git.branch_origins).to eq("20260301120000_add_cherries.rb" => "feature/PS-7")
        expect(branch_queries).to eq(["older00"])
      end
    end

    context "when the plain log finds the commit" do
      let(:plain_sha) { "plain00\n" }

      it "never runs the merge-aware log" do
        expect(git.branch_origins).to eq("20260301120000_add_cherries.rb" => "feature/PS-7")
        expect(branch_queries).to eq(["plain00"])
        expect(Railbow::GitUtils).not_to have_received(:capture2)
          .with("log", "--diff-filter=AR", "--format=%H", "-m", "--", path)
      end
    end

    context "when neither log finds the commit" do
      it "leaves the file without an origin" do
        expect(git.branch_origins).to be_empty
        expect(branch_queries).to be_empty
      end
    end
  end
end
