# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/module/attribute_accessors"
require "rails/info"
require "railbow/about_formatter"

# A railbow bug must never break the Rails command it decorates: any error in
# railbow's own rendering falls back to the stock Rails output.
RSpec.describe "falling back to the default Rails output" do
  # Colors on through RBW_FORCE rather than a stubbed plain?, so the switch-off
  # after a failure is exercised for real.
  before do
    allow(Railbow::Params).to receive(:plain?).and_return(false)
    allow(Railbow::Params).to receive(:force?).and_return(true)
  end

  describe "Railbow.guard" do
    it "returns the block's result when nothing fails" do
      expect(Railbow.guard(-> { :plain }) { :railbow }).to eq(:railbow)
    end

    it "returns the fallback's result when the block raises" do
      result = nil
      expect { result = Railbow.guard(-> { :plain }) { raise "boom" } }.to output.to_stderr
      expect(result).to eq(:plain)
    end

    it "names the error on stderr" do
      expect { Railbow.guard(-> {}) { raise ArgumentError, "boom" } }
        .to output(/railbow: ArgumentError: boom.*default Rails output/m).to_stderr
    end

    it "switches railbow off for the rest of the process" do
      expect { Railbow.guard(-> {}) { raise "boom" } }.to output.to_stderr

      expect(Railbow.plain?).to be(true)
    end

    it "warns only for the first failure" do
      expect { Railbow.guard(-> {}) { raise "first" } }.to output(/first/).to_stderr
      expect { Railbow.guard(-> {}) { raise "second" } }.not_to output.to_stderr
    end

    it "lets errors from the fallback itself propagate" do
      expect {
        Railbow.guard(-> { raise IOError, "from rails" }) { raise "boom" }
      }.to raise_error(IOError, "from rails").and output.to_stderr
    end

    it "does not swallow exits" do
      expect { Railbow.guard(-> {}) { Kernel.exit(1) } }.to raise_error(SystemExit)
    end
  end

  describe "rails about" do
    before { Rails::Info.singleton_class.prepend(Railbow::AboutFormatter) }

    it "prints the stock Rails table when rendering fails" do
      allow_any_instance_of(Railbow::Formatters::Base).to receive(:bold).and_raise(NoMethodError, "boom")

      output = nil
      expect { output = Rails::Info.to_s }.to output(/boom/).to_stderr
      expect(output).to start_with("About your application's environment")
    end
  end

  describe "migrations" do
    # Rails' own Migration output methods, which railbow is prepended onto.
    let(:rails_migration) do
      Class.new do
        attr_reader :output

        def initialize
          @output = []
        end

        def write(text = "")
          @output << text
        end

        def say(message, subitem = false)
          write "#{subitem ? "   ->" : "--"} #{message}"
        end

        def say_with_time(message)
          say(message)
          result = yield
          say "0.0010s", :subitem
          result
        end
      end
    end

    let(:migration) do
      klass = Class.new(rails_migration) { prepend Railbow::MigrationFormatter }
      stub_const("FallbackMigration", klass)
      klass.new
    end

    before do
      allow_any_instance_of(Railbow::Formatters::Base)
        .to receive(:format_timing).and_raise(NoMethodError, "boom")
    end

    it "runs the migration body once when formatting its timing fails" do
      calls = 0
      expect { migration.say_with_time("create_table(:apples)") { calls += 1 } }.to output.to_stderr

      expect(calls).to eq(1)
    end

    it "prints the lines Rails would have" do
      expect { migration.say_with_time("create_table(:apples)") { 3 } }.to output.to_stderr

      expect(migration.output.first).to eq("-- create_table(:apples)")
      expect(migration.output).to include("   -> 3 rows")
    end

    it "returns the migration body's result" do
      result = nil
      expect { result = migration.say_with_time("create_table(:apples)") { 3 } }.to output.to_stderr

      expect(result).to eq(3)
    end

    it "lets an error from the migration body raise untouched" do
      allow_any_instance_of(Railbow::Formatters::Base).to receive(:format_timing).and_call_original

      expect { migration.say_with_time("create_table(:apples)") { raise ArgumentError, "bad migration" } }
        .to raise_error(ArgumentError, "bad migration")
      expect(Railbow.failure).to be_nil
    end
  end
end
