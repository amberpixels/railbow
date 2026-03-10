# frozen_string_literal: true

require "spec_helper"
require "railbow/init"
require "rake"
require "tmpdir"

RSpec.describe "railbow:init rake task" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("railbow/tasks/init", $LOAD_PATH)
  end

  after { Railbow::Config.reset! }

  let(:task) { Rake::Task["railbow:init"] }

  before { task.reenable }

  it "delegates to Railbow::Init.run" do
    expect(Railbow::Init).to receive(:run)
    task.invoke
  end
end
