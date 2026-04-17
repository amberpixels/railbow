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
      # users from DDL, settings from first matching model call; Audit dropped (cap = 2).
      # Note: `Audit.find_each` would match the pattern but only `find_each` is hit first
      # for Setting; we stop after adding settings.
      expect(described_class.extract_tables_from_content(content)).to eq(["users", "settings"])
    end

    it "does not match instance-method calls on lowercase receivers" do
      content = "s.update_column(:x, 1)"
      expect(described_class.extract_tables_from_content(content)).to eq([])
    end
  end
end
