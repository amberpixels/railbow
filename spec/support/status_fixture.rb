# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

# Builds a deterministic db:migrate:status render: real migration files on disk
# (so table extraction runs for real) and a git stub that answers every command
# migrate_status issues. Used by the golden spec that guards the multi-database
# refactor - the render it produces must survive the extraction byte for byte.
#
# Include into an example group; the helpers need the example's own `allow`.
module StatusFixture
  DEV_NAME = "Test Dev"
  DEV_EMAIL = "dev@example.test"
  OTHER_NAME = "Other Dev"
  OTHER_EMAIL = "other@example.test"

  NO_FILE = "********** NO FILE **********"

  GOLDEN_DIR = File.expand_path("../fixtures/golden", __dir__)

  # Two months so the calendar draws a separator, one pending row, one applied
  # row whose file is gone, and two authors so highlighting can differ per row.
  MIGRATIONS = [
    {version: "20260202145343", name: "AddWeightFieldToAnimals", status: "up",
     author: :me, body: "add_column :animals, :weight, :integer"},
    {version: "20260203134528", name: "CreateVaccinationRecords", status: "up",
     author: :other, body: "create_table :vaccination_records"},
    {version: "20260210183902", name: "CreatePetTags", status: "up",
     author: :other, landed: "2026-03-04", body: "create_table :pet_tags"},
    {version: "20260303120000", name: "AddBreedRestrictionsToAdoptionPolicies", status: "up",
     author: :me, landed: "2026-03-13",
     body: "add_column :adoption_policies, :breed, :string\n    add_index :adoption_policies, :breed"},
    {version: "20260313132325", name: "CreateVeterinaryAppointments", status: "up",
     author: :me,
     body: "create_table :veterinary_appointments\n    add_foreign_key :veterinary_appointments, :animals"},
    {version: "20260318090000", name: "AddNotesToVaccinationRecords", status: "down",
     author: :other, body: "add_column :vaccination_records, :notes, :text"}
  ].freeze

  GHOST_VERSION = "20260315110000"

  MigrationDouble = Struct.new(:version, :filename)

  # Writes the migration files to a tmp dir and yields it. migrate_dir is
  # derived from these filenames, so the git stub keys off the same names.
  def with_migration_files
    Dir.mktmpdir("railbow-status") do |dir|
      migrate_dir = File.join(dir, "migrate")
      FileUtils.mkdir_p(migrate_dir)
      MIGRATIONS.each do |m|
        File.write(File.join(migrate_dir, filename_for(m)), <<~RUBY)
          class #{m[:name]} < ActiveRecord::Migration[8.0]
            def change
              #{m[:body]}
            end
          end
        RUBY
      end
      yield migrate_dir
    end
  end

  def filename_for(migration)
    "#{migration[:version]}_#{snake_case(migration[:name])}.rb"
  end

  def snake_case(str)
    str.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  end

  # The rows Rails' migrations_status returns: every file, plus one applied
  # version whose file no longer exists.
  def fixture_db_list
    rows = MIGRATIONS.map { |m| [m[:status], m[:version], m[:name]] }
    rows << ["up", GHOST_VERSION, NO_FILE]
    rows.sort_by { |_, version, _| version }
  end

  def migration_doubles(dir)
    MIGRATIONS.map { |m| MigrationDouble.new(m[:version], File.join(dir, filename_for(m))) }
  end

  def author_log
    MIGRATIONS.map { |m|
      name, email = (m[:author] == :me) ? [DEV_NAME, DEV_EMAIL] : [OTHER_NAME, OTHER_EMAIL]
      "COMMIT:#{name}\t#{email}\nA\t#{filename_for(m)}\n"
    }.join
  end

  def landed_log
    MIGRATIONS.filter_map { |m|
      next unless m[:landed]
      "COMMIT:#{m[:landed]}T10:00:00+00:00\nA\t#{filename_for(m)}\n"
    }.join
  end

  # Answers every git command migrate_status can issue. Anything unrecognized
  # comes back empty and failed, the same shape GitUtils yields when git is
  # missing, so an unstubbed command degrades instead of raising.
  def stub_git
    ok = instance_double(Process::Status, success?: true)
    failed = instance_double(Process::Status, success?: false)

    allow(Railbow::GitUtils).to receive(:capture2) do |*args|
      case args
      in ["config", "user.email"] then ["#{DEV_EMAIL}\n", ok]
      in ["config", "user.name"] then ["#{DEV_NAME}\n", ok]
      in ["log", "--format=COMMIT:%aN\t%aE", *] then [author_log, ok]
      in ["log", "--first-parent", *] then [landed_log, ok]
      in ["rev-parse", "--abbrev-ref", "HEAD"] then ["main\n", ok]
      in ["symbolic-ref", *] then ["refs/remotes/origin/main\n", ok]
      in ["merge-base", *] then ["abc1234567\n", ok]
      in ["diff", *] then ["", ok]
      in ["status", "--porcelain", *] then ["", ok]
      else ["", failed]
      end
    end

    allow(Railbow::GitUtils).to receive(:capture3).and_return(["", "", failed])
  end

  def golden_path(name)
    File.join(GOLDEN_DIR, name)
  end

  # Renders must not depend on the machine running them. Without this, a
  # developer with a ~/.config/railbow/config.yml gets different output than
  # CI, and regenerating the golden fixture would bake their personal settings
  # into the repository.
  def isolate_config
    allow(Railbow::Config).to receive(:config_files).and_return([])
    Railbow::Config.reset!
  end

  def capture_stdout
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    yield
    captured.string
  ensure
    $stdout = original
  end
end
