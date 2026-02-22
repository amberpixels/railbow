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
  end
end
