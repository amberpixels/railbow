# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Railbow::MigrationParser do
  def write_migration(content)
    file = Tempfile.new(["migration", ".rb"])
    file.write(content)
    file.close
    file
  end

  describe ".extract_tables" do
    it "extracts table from create_table with symbol" do
      file = write_migration("create_table :products do |t|; end")
      expect(described_class.extract_tables(file.path)).to eq(["products"])
    ensure
      file&.unlink
    end

    it "extracts table from create_table with string" do
      file = write_migration('create_table "products" do |t|; end')
      expect(described_class.extract_tables(file.path)).to eq(["products"])
    ensure
      file&.unlink
    end

    it "extracts table from add_column" do
      file = write_migration("add_column :users, :email, :string")
      expect(described_class.extract_tables(file.path)).to eq(["users"])
    ensure
      file&.unlink
    end

    it "extracts multiple tables from different operations" do
      content = <<~RUBY
        create_table :orders do |t|
          t.string :name
        end
        add_foreign_key :orders, :users
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to contain_exactly("orders", "users")
    ensure
      file&.unlink
    end

    it "deduplicates tables" do
      content = <<~RUBY
        create_table :products do |t|
          t.string :name
        end
        add_column :products, :price, :decimal
        add_index :products, :name
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to eq(["products"])
    ensure
      file&.unlink
    end

    it "returns empty array for nil filepath" do
      expect(described_class.extract_tables(nil)).to eq([])
    end

    it "returns empty array for empty filepath" do
      expect(described_class.extract_tables("")).to eq([])
    end

    it "returns empty array for missing file" do
      expect(described_class.extract_tables("/nonexistent/path.rb")).to eq([])
    end

    it "extracts both tables from add_foreign_key" do
      file = write_migration("add_foreign_key :orders, :products")
      expect(described_class.extract_tables(file.path)).to contain_exactly("orders", "products")
    ensure
      file&.unlink
    end

    it "extracts table from add_reference" do
      file = write_migration("add_reference :orders, :user, foreign_key: true")
      expect(described_class.extract_tables(file.path)).to eq(["orders"])
    ensure
      file&.unlink
    end

    it "extracts table from drop_table" do
      file = write_migration("drop_table :legacy_items")
      expect(described_class.extract_tables(file.path)).to eq(["legacy_items"])
    ensure
      file&.unlink
    end

    it "extracts table from execute with UPDATE SQL" do
      content = <<~RUBY
        execute <<~SQL.squish
          UPDATE color_preferences
          SET colorable_type = 'VisitKind'
          WHERE colorable_type = 'SchedulerVisitKind'
        SQL
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to eq(["color_preferences"])
    ensure
      file&.unlink
    end

    it "extracts table from execute with INSERT INTO SQL" do
      content = <<~RUBY
        execute "INSERT INTO audit_logs (action) VALUES ('migrated')"
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to eq(["audit_logs"])
    ensure
      file&.unlink
    end

    it "extracts table from execute with DELETE FROM SQL" do
      content = <<~RUBY
        execute "DELETE FROM old_records WHERE created_at < '2020-01-01'"
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to eq(["old_records"])
    ensure
      file&.unlink
    end

    it "extracts table from execute with ALTER TABLE SQL" do
      content = <<~RUBY
        execute "ALTER TABLE users ADD CONSTRAINT chk_email CHECK (email IS NOT NULL)"
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to eq(["users"])
    ensure
      file&.unlink
    end

    it "extracts multiple tables from mixed Ruby DSL and SQL" do
      content = <<~RUBY
        add_column :users, :status, :string
        execute "UPDATE settings SET value = 'new' WHERE key = 'migration'"
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to contain_exactly("users", "settings")
    ensure
      file&.unlink
    end

    it "deduplicates tables from SQL and Ruby DSL" do
      content = <<~RUBY
        add_column :users, :status, :string
        execute "UPDATE users SET status = 'active'"
      RUBY
      file = write_migration(content)
      expect(described_class.extract_tables(file.path)).to eq(["users"])
    ensure
      file&.unlink
    end
  end

  describe ".extract_tables_from_content" do
    it "extracts tables directly from content string" do
      content = "create_table :users do |t|\n  t.string :name\nend"
      expect(described_class.extract_tables_from_content(content)).to eq(["users"])
    end

    it "returns empty array for nil or empty content" do
      expect(described_class.extract_tables_from_content(nil)).to eq([])
      expect(described_class.extract_tables_from_content("")).to eq([])
    end
  end

  describe "keyword-argument table detection" do
    it "extracts table from a helper call with table: keyword and symbol value" do
      content = "convert_to_monthly_partitions(table: :apples, indexes: INDEXES)"
      expect(described_class.extract_tables_from_content(content)).to eq(["apples"])
    end

    it "extracts table from table: keyword with string value" do
      content = 'convert_to_monthly_partitions(table: "apples")'
      expect(described_class.extract_tables_from_content(content)).to eq(["apples"])
    end

    it "extracts both tables from remove_foreign_key with to_table: keyword" do
      content = "remove_foreign_key :accounts, to_table: :owners"
      expect(described_class.extract_tables_from_content(content)).to contain_exactly("accounts", "owners")
    end

    it "does not extract from:/to: values as tables" do
      content = 'change_column_default :users, :status, from: nil, to: "active"'
      expect(described_class.extract_tables_from_content(content)).to eq(["users"])
    end

    it "counts keyword tables toward the model-detection guard" do
      content = <<~RUBY
        partition_helper(table: :orders)
        partition_helper(table: :users)
        Setting.find_each { |s| s.update_column(:x, 1) }
      RUBY
      expect(described_class.extract_tables_from_content(content)).to contain_exactly("orders", "users")
    end

    it "extracts table from a realistic partition-conversion migration" do
      content = <<~RUBY
        class PartitionApplesByMonth < ActiveRecord::Migration[8.1]
          include PartitionConversion

          # Rewrites the table into a partitioned one (ALTER TABLE is not enough:
          # postgres cannot convert a plain table in place).
          INDEXES = [
            [:banana_id, "index_apples_on_banana_id"],
            [:created_at, "index_apples_on_created_at"]
          ].freeze

          def up
            convert_to_monthly_partitions(table: :apples, indexes: INDEXES)
          end
        end
      RUBY
      expect(described_class.extract_tables_from_content(content)).to eq(["apples"])
    end
  end

  describe "comment stripping" do
    it "ignores SQL keywords inside comments" do
      content = <<~RUBY
        # This used to run ALTER TABLE ghosts, kept for reference.
        def up; end
      RUBY
      expect(described_class.extract_tables_from_content(content)).to eq([])
    end

    it "ignores commented-out DSL calls" do
      content = "# create_table :ghosts do |t|; end"
      expect(described_class.extract_tables_from_content(content)).to eq([])
    end

    it "keeps content after string interpolation on the same line" do
      content = <<~'RUBY'
        execute "COMMENT ON TABLE #{tbl} IS 'x'; UPDATE settings SET a = 1"
      RUBY
      expect(described_class.extract_tables_from_content(content)).to eq(["settings"])
    end
  end

  describe "model-based table detection" do
    it "infers table name from ActiveRecord model with find_each" do
      content = <<~RUBY
        class RemapSettings < ActiveRecord::Migration[8.1]
          def up
            Setting.find_each { |s| s.update_column(:x, 1) }
          end
        end
      RUBY
      expect(described_class.extract_tables_from_content(content)).to eq(["settings"])
    end

    it "pluralizes CamelCase model names" do
      content = "OrderItem.where(active: true).update_all(active: false)"
      expect(described_class.extract_tables_from_content(content)).to eq(["order_items"])
    end

    it "uses last namespace segment for scoped models" do
      content = "Billing::Invoice.find_each { |i| i.save! }"
      expect(described_class.extract_tables_from_content(content)).to eq(["invoices"])
    end

    it "skips model detection when DDL already found ≥2 tables" do
      content = <<~RUBY
        add_column :users, :status, :string
        add_column :posts, :status, :string
        Setting.find_each { |s| s.update_column(:x, 1) }
      RUBY
      expect(described_class.extract_tables_from_content(content)).to contain_exactly("users", "posts")
    end

    it "supplements a single DDL table with one model table (capped at 2)" do
      content = <<~RUBY
        add_column :users, :status, :string
        Setting.find_each { |s| s.update_column(:x, 1) }
        Audit.find_each { |a| a.destroy }
      RUBY
      # users from DDL, settings from the first model call; Audit falls past the cap.
      expect(described_class.extract_tables_from_content(content)).to eq(["users", "settings"])
    end

    it "does not match instance-method calls on lowercase receivers" do
      content = "s.update_column(:x, 1)"
      expect(described_class.extract_tables_from_content(content)).to eq([])
    end
  end

  describe "schema-qualified tables" do
    def tables(content)
      described_class.extract_tables_from_content(content)
    end

    it "keeps the schema of a table named in the DSL" do
      expect(tables('add_column "reporting.events", :region_id, :integer')).to eq(["reporting.events"])
    end

    it "keeps the schema on both sides of a foreign key" do
      content = 'add_foreign_key "reporting.events", "reporting.regions"'
      expect(tables(content)).to contain_exactly("reporting.events", "reporting.regions")
    end

    it "reads a single-quoted table name" do
      expect(tables("add_column 'reporting.events', :region_id, :integer")).to eq(["reporting.events"])
      expect(tables("add_foreign_key 'orders', 'users'")).to contain_exactly("orders", "users")
    end

    it "does not repeat a schema-qualified table for a model of the same table" do
      content = <<~RUBY
        add_column "reporting.events", :region_id, :integer
        Reporting::Event.update_all(region_id: 1)
      RUBY
      expect(tables(content)).to eq(["reporting.events"])
    end

    it "keeps the schema of a table named by keyword" do
      expect(tables('partition_monthly(table: "reporting.events")')).to eq(["reporting.events"])
    end

    it "leaves a method call on a keyword value out of the name" do
      expect(tables("partition_monthly(table: apples.to_s)")).to eq(["apples"])
    end

    it "keeps the schema of a table named in SQL" do
      expect(tables('execute "ALTER TABLE reporting.events ADD COLUMN x int"')).to eq(["reporting.events"])
    end

    it "reads a quoted schema and table in SQL" do
      content = %q(execute 'UPDATE "reporting"."events" SET region_id = 1')
      expect(tables(content)).to eq(["reporting.events"])
    end

    it "reads quotes escaped inside a Ruby string" do
      content = 'execute "DELETE FROM \\"reporting\\".\\"events\\""'
      expect(tables(content)).to eq(["reporting.events"])
    end

    it "shows a table in the public schema by its bare name" do
      content = <<~RUBY
        add_column "public.events", :region_id, :integer
        execute "UPDATE public.events SET region_id = 1"
      RUBY
      expect(tables(content)).to eq(["events"])
    end

    it "does not read a method called on the SQL string as a table" do
      expect(tables('execute "DELETE FROM events".squish')).to eq(["events"])
    end

    it "reads ALTER TABLE with IF EXISTS and ONLY" do
      expect(tables('execute "ALTER TABLE IF EXISTS ONLY reporting.events ADD COLUMN x int"')).to eq(["reporting.events"])
    end
  end

  describe "indexes and views in SQL" do
    def tables(content)
      described_class.extract_tables_from_content(content)
    end

    it "reads the table of CREATE INDEX ... ON ONLY" do
      content = 'execute "CREATE INDEX idx ON ONLY reporting.events (created_at)"'
      expect(tables(content)).to eq(["reporting.events"])
    end

    it "reads the table of a unique concurrent index" do
      content = 'execute "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_apples_on_name ON apples (name)"'
      expect(tables(content)).to eq(["apples"])
    end

    it "reads the name of a view" do
      expect(tables('execute "CREATE VIEW reporting.daily AS SELECT 1"')).to eq(["reporting.daily"])
    end

    it "reads the name of a replaced materialized view" do
      content = 'execute "CREATE OR REPLACE MATERIALIZED VIEW daily_totals AS SELECT 1"'
      expect(tables(content)).to eq(["daily_totals"])
    end
  end
end
