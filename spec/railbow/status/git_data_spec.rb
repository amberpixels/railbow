# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"
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

  describe "uncommitted files" do
    let(:ok) { instance_double(Process::Status, success?: true) }
    let(:failed) { instance_double(Process::Status, success?: false) }
    let(:widgets) { "20261111003117_create_widgets.rb" }
    let(:gadgets) { "20261111135204_create_gadgets.rb" }
    let(:porcelain) { "" }
    let(:base_tree) { "db/migrate/#{widgets}\n" }
    let(:merge_base) { ["base000\n", ok] }

    # `status --porcelain` compares the tree with HEAD; the merge-base's own
    # file list is what tells a new file from one the base branch already has.
    before do
      allow(Railbow::GitUtils).to receive(:capture2) do |*args|
        case args
        in ["symbolic-ref", *] then ["refs/remotes/origin/main\n", ok]
        in ["merge-base", "HEAD", "main"] then merge_base
        in ["ls-tree", "-r", "--name-only", "base000", "--", "db/migrate"] then [base_tree, ok]
        in ["diff", "--name-status", *] then ["", ok]
        in ["rev-parse", "--abbrev-ref", "HEAD"] then ["feature-x\n", ok]
        in ["status", "--porcelain", *] then [porcelain, ok]
        else ["", failed]
        end
      end
      allow(Railbow::GitUtils).to receive(:capture3).and_return(["", "", failed])
    end

    subject(:git) do
      described_class.new(migrate_dir: "db/migrate", author_enabled: false, diff_enabled: true)
    end

    def branch_files
      described_class.branch_files(["db/migrate"])
    end

    context "when a rename back to a base-branch filename is staged" do
      let(:porcelain) { "R  db/migrate/20261111135205_create_widgets.rb -> db/migrate/#{widgets}\n" }

      it "does not attribute the file to the current branch" do
        expect(git.branch_origins).not_to have_key(widgets)
        expect(branch_files).not_to include(widgets)
      end

      it "still reports the file as uncommitted" do
        expect(git.uncommitted_files).to include(widgets)
      end
    end

    context "when a rename back to a base-branch filename is not staged" do
      let(:porcelain) { " D db/migrate/20261111135205_create_widgets.rb\n?? db/migrate/#{widgets}\n" }

      it "does not attribute the file to the current branch" do
        expect(git.branch_origins).not_to have_key(widgets)
        expect(branch_files).not_to include(widgets)
        expect(git.uncommitted_files).to include(widgets)
      end
    end

    context "when a new migration is staged" do
      let(:porcelain) { "A  db/migrate/#{gadgets}\n" }

      it "attributes it to the current branch" do
        expect(git.branch_origins).to eq(gadgets => "feature-x")
        expect(branch_files).to include(gadgets)
      end
    end

    context "when a new migration is untracked" do
      let(:porcelain) { "?? db/migrate/#{gadgets}\n" }

      it "attributes it to the current branch" do
        expect(git.branch_origins).to eq(gadgets => "feature-x")
        expect(branch_files).to include(gadgets)
      end
    end

    context "when an edit to an existing migration is staged" do
      let(:porcelain) { "M  db/migrate/#{widgets}\n" }

      it "badges the file but does not count it as added by the branch" do
        expect(git.branch_origins).to eq(widgets => "feature-x")
        expect(branch_files).to be_empty
        expect(Railbow::GitUtils).not_to have_received(:capture2).with("ls-tree", any_args)
      end
    end

    context "when there is no merge-base to compare with" do
      let(:porcelain) { "A  db/migrate/#{gadgets}\n?? db/migrate/#{widgets}\n" }
      let(:merge_base) { ["", failed] }

      it "counts every new file, as there is nothing to compare against" do
        expect(git.branch_origins).to eq(gadgets => "feature-x", widgets => "feature-x")
        expect(branch_files).to include(gadgets, widgets)
      end
    end
  end

  # Real git, no stubs: the fix rests on what git itself reports once a
  # base-branch migration, renamed while merging, is renamed back.
  describe "in a repository where a merged-in migration was renamed" do
    let(:widgets) { "20261111003117_create_widgets.rb" }
    let(:renamed) { "20261111135205_create_widgets.rb" }
    let(:gadgets) { "20261111135204_create_gadgets.rb" }

    def git!(*args)
      out, status = Open3.capture2e(
        "git", "-c", "user.name=Tester", "-c", "user.email=tester@example.test",
        "-c", "commit.gpgsign=false", *args
      )
      raise "git #{args.join(" ")} failed: #{out}" unless status.success?
    end

    def commit_file(name, message)
      File.write("db/migrate/#{name}", "# #{name}\n")
      git!("add", "db/migrate/#{name}")
      git!("commit", "-q", "-m", message)
    end

    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          git!("init", "-q", "-b", "main", ".")
          git!("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
          FileUtils.mkdir_p("db/migrate")
          commit_file("20260101000000_create_apples.rb", "apples")
          git!("checkout", "-q", "-b", "feature-x")
          commit_file(gadgets, "gadgets")
          git!("checkout", "-q", "main")
          commit_file(widgets, "widgets")
          git!("checkout", "-q", "feature-x")
          git!("merge", "-q", "--no-commit", "--no-ff", "main")
          git!("mv", "db/migrate/#{widgets}", "db/migrate/#{renamed}")
          git!("commit", "-q", "-m", "merge main")
          example.run
        end
      end
    end

    subject(:git) do
      described_class.new(migrate_dir: "db/migrate", author_enabled: false, diff_enabled: true)
    end

    def branch_files
      described_class.branch_files(["db/migrate"])
    end

    it "leaves a staged rename back to the base filename off the branch" do
      git!("mv", "db/migrate/#{renamed}", "db/migrate/#{widgets}")

      expect(git.branch_origins).not_to have_key(widgets)
      expect(git.branch_origins).to have_key(gadgets)
      expect(branch_files).not_to include(widgets)
      expect(git.uncommitted_files).to include(widgets)
    end

    it "leaves an unstaged rename back to the base filename off the branch" do
      File.rename("db/migrate/#{renamed}", "db/migrate/#{widgets}")

      expect(git.branch_origins).not_to have_key(widgets)
      expect(branch_files).not_to include(widgets)
      expect(git.uncommitted_files).to include(widgets)
    end

    it "keeps a new uncommitted migration on the branch, staged or not" do
      File.write("db/migrate/20261111140000_create_pears.rb", "# pears\n")
      File.write("db/migrate/20261111150000_create_plums.rb", "# plums\n")
      git!("add", "db/migrate/20261111140000_create_pears.rb")

      expect(git.branch_origins).to include(
        "20261111140000_create_pears.rb" => "feature-x",
        "20261111150000_create_plums.rb" => "feature-x"
      )
    end
  end
end
