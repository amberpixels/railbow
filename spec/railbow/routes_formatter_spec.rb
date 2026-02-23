# frozen_string_literal: true

require "spec_helper"
require "railbow/routes_formatter"

# Minimal stub for ActionDispatch::Routing::ConsoleFormatter::Sheet
# so we can test the prepended module in isolation.
module ActionDispatch
  module Routing
    module ConsoleFormatter
      class Sheet
        def initialize
          @buffer = []
        end

        def result
          @buffer.join("\n")
        end

        def section_title(title)
          @buffer << "#{title}:"
        end

        def section(routes)
          header_lengths = ["Prefix", "Verb", "URI Pattern"].map(&:length)
          name_width, verb_width, path_width = widths(routes).zip(header_lengths).map(&:max)

          header = "#{"Prefix".rjust(name_width)} #{"Verb".ljust(verb_width)} #{"URI Pattern".ljust(path_width)} Controller#Action"
          @buffer << header

          rows = routes.map do |r|
            "#{r[:name].rjust(name_width)} #{r[:verb].ljust(verb_width)} #{r[:path].ljust(path_width)} #{r[:reqs]}"
          end
          @buffer << rows
        end

        def header(routes)
          header_lengths = ["Prefix", "Verb", "URI Pattern"].map(&:length)
          name_width, verb_width, path_width = widths(routes).zip(header_lengths).map(&:max)

          @buffer << "#{"Prefix".rjust(name_width)} #{"Verb".ljust(verb_width)} #{"URI Pattern".ljust(path_width)} Controller#Action"
        end

        private

        def widths(routes)
          [routes.map { |r| r[:name].length }.max || 0,
            routes.map { |r| r[:verb].length }.max || 0,
            routes.map { |r| r[:path].length }.max || 0]
        end
      end
    end
  end
end

# Prepend the module under test
ActionDispatch::Routing::ConsoleFormatter::Sheet.prepend(Railbow::RoutesFormatter)

RSpec.describe Railbow::RoutesFormatter do
  let(:formatter) { ActionDispatch::Routing::ConsoleFormatter::Sheet.new }

  let(:sample_routes) do
    [
      {name: "users", verb: "GET", path: "/users(.:format)", reqs: "users#index"},
      {name: "", verb: "POST", path: "/users(.:format)", reqs: "users#create"},
      {name: "edit_user", verb: "GET", path: "/users/:id/edit(.:format)", reqs: "users#edit"},
      {name: "", verb: "PATCH", path: "/users/:id(.:format)", reqs: "users#update"},
      {name: "", verb: "PUT", path: "/users/:id(.:format)", reqs: "users#update"},
      {name: "", verb: "DELETE", path: "/users/:id(.:format)", reqs: "users#destroy"}
    ]
  end

  before do
    ENV.delete("HELP")
    ENV.delete("GROUP")
    ENV.delete("COMPACT")
    ENV.delete("PLAIN")
    ENV.delete("NO_COLOR")
    ENV.delete("CLAUDECODE")
    ENV.delete("CI")
  end

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  describe "default grouping by controller" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "groups routes by controller by default" do
      routes = [
        {name: "users", verb: "GET", path: "/users", reqs: "users#index"},
        {name: "posts", verb: "GET", path: "/posts", reqs: "posts#index"},
        {name: "", verb: "POST", path: "/users", reqs: "users#create"}
      ]
      formatter.section(routes)
      result = strip_ansi(formatter.result)
      expect(result).to include("── users ──")
      expect(result).to include("── posts ──")
    end

    it "puts non-controller routes into (other) group at the end" do
      routes = [
        {name: "users", verb: "GET", path: "/users", reqs: "users#index"},
        {name: "system_stats", verb: "GET", path: "/system_stats", reqs: "redirect(301, system)"},
        {name: "", verb: "POST", path: "/users", reqs: "users#create"}
      ]
      formatter.section(routes)
      result = strip_ansi(formatter.result)
      expect(result).to include("── users ──")
      expect(result).to include("── (other) ──")
      # (other) should come after users
      expect(result.index("── users ──")).to be < result.index("── (other) ──")
    end

    it "renders section headers with bold+cyan" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("#{Railbow::RoutesFormatter::BOLD}#{Railbow::RoutesFormatter::CYAN}")
      expect(result).to include("users")
    end
  end

  describe "GROUP=none flat list" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "produces flat output without section headers" do
      ENV["GROUP"] = "none"
      routes = [
        {name: "users", verb: "GET", path: "/users", reqs: "users#index"},
        {name: "posts", verb: "GET", path: "/posts", reqs: "posts#index"}
      ]
      formatter.section(routes)
      result = strip_ansi(formatter.result)
      expect(result).not_to include("──")
      expect(result).to include("/users")
      expect(result).to include("/posts")
    end
  end

  describe "verb colorization" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "colors GET in green" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("\e[32mGET\e[0m")
    end

    it "colors POST in yellow" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("\e[33mPOST\e[0m")
    end

    it "colors PATCH in cyan" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("\e[36mPATCH\e[0m")
    end

    it "colors PUT in cyan" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("\e[36mPUT\e[0m")
    end

    it "colors DELETE in red" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("\e[31mDELETE\e[0m")
    end

    it "handles multi-verb routes like GET|POST" do
      routes = [{name: "root", verb: "GET|POST", path: "/", reqs: "home#index"}]
      formatter.section(routes)
      result = formatter.result
      expect(result).to include("\e[32mGET\e[0m")
      expect(result).to include("\e[33mPOST\e[0m")
      expect(result).to include("\e[2m|\e[0m")
    end
  end

  describe "path dynamic segment highlighting" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "highlights :id segments in cyan" do
      routes = [{name: "user", verb: "GET", path: "/users/:id", reqs: "users#show"}]
      formatter.section(routes)
      expect(formatter.result).to include("\e[36m:id\e[0m")
    end

    it "highlights :user_id segments in cyan" do
      routes = [{name: "", verb: "GET", path: "/users/:user_id/posts", reqs: "posts#index"}]
      formatter.section(routes)
      expect(formatter.result).to include("\e[36m:user_id\e[0m")
    end

    it "highlights *path glob segments in cyan" do
      routes = [{name: "", verb: "GET", path: "/files/*path", reqs: "files#show"}]
      formatter.section(routes)
      expect(formatter.result).to include("\e[36m*path\e[0m")
    end
  end

  describe "controller#action formatting" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "bolds the controller and dims the hash" do
      routes = [{name: "users", verb: "GET", path: "/users", reqs: "users#index"}]
      formatter.section(routes)
      result = formatter.result
      expect(result).to include("\e[1musers\e[0m")
      expect(result).to include("\e[2m#\e[0m")
      expect(result).to include("index")
    end

    it "dims non-controller endpoints (Rack apps)" do
      routes = [{name: "", verb: "", path: "/sidekiq", reqs: "Sidekiq::Web"}]
      formatter.section(routes)
      result = formatter.result
      expect(result).to include("\e[2mSidekiq::Web\e[0m")
    end
  end

  describe "prefix handling" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "dims route prefixes" do
      routes = [{name: "users", verb: "GET", path: "/users", reqs: "users#index"}]
      formatter.section(routes)
      result = formatter.result
      expect(result).to include("\e[2musers\e[0m")
    end

    it "handles empty prefixes" do
      routes = [{name: "", verb: "GET", path: "/users", reqs: "users#index"}]
      formatter.section(routes)
      result = formatter.result
      expect(strip_ansi(result)).to include("/users")
    end

    it "shows full prefix in last column without truncation" do
      long_name = "create_form_requisition_automation_step_insurance_limit_constraints"
      routes = [{name: long_name, verb: "GET", path: "/foo", reqs: "foo#bar"}]
      formatter.section(routes)
      plain = strip_ansi(formatter.result)
      expect(plain).to include(long_name)
    end
  end

  describe "compact mode (format suffix stripping)" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "strips (.:format) from paths by default" do
      routes = [{name: "users", verb: "GET", path: "/users(.:format)", reqs: "users#index"}]
      formatter.section(routes)
      plain = strip_ansi(formatter.result)
      expect(plain).not_to include("(.:format)")
      expect(plain).to include("/users")
    end

    it "keeps (.:format) when COMPACT=0" do
      ENV["COMPACT"] = "0"
      routes = [{name: "users", verb: "GET", path: "/users(.:format)", reqs: "users#index"}]
      formatter.section(routes)
      plain = strip_ansi(formatter.result)
      expect(plain).to include("(.:format)")
    end
  end

  describe "section_title formatting" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "bolds and colors engine names" do
      formatter.section_title("Routes for Devise::Engine")
      result = formatter.result
      expect(result).to include("\e[1m\e[36mRoutes for Devise::Engine:\e[0m")
    end
  end

  describe "non-TTY passthrough" do
    before { allow($stdout).to receive(:tty?).and_return(false) }

    it "falls back to Rails default output without ANSI codes" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).not_to include("\e[")
    end

    it "falls back to Rails default section_title without ANSI codes" do
      formatter.section_title("Routes for Devise::Engine")
      result = formatter.result
      expect(result).not_to include("\e[")
    end

    it "uses Rails default column layout (Prefix first)" do
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("Prefix")
      expect(result).to include("Verb")
      expect(result).to include("URI Pattern")
      expect(result).to include("Controller#Action")
    end
  end

  describe "column alignment" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "preserves column alignment with varying-width content" do
      ENV["GROUP"] = "none"
      routes = [
        {name: "a", verb: "GET", path: "/short", reqs: "a#b"},
        {name: "long_prefix_name", verb: "DELETE", path: "/very/long/path/:id/edit", reqs: "long_controller#action"}
      ]
      formatter.section(routes)
      lines = formatter.result.split("\n").reject(&:empty?)
      plain_lines = lines.map { |l| strip_ansi(l) }
      verb_positions = plain_lines.map { |l| l.index("GET") || l.index("DELETE") }
      expect(verb_positions.compact.uniq.size).to eq(1)
    end

    it "keeps alignment even with truncated prefixes" do
      ENV["GROUP"] = "none"
      routes = [
        {name: "short", verb: "GET", path: "/a", reqs: "a#b"},
        {name: "a_very_long_prefix_that_exceeds_the_max_width_limit", verb: "POST", path: "/b", reqs: "c#d"}
      ]
      formatter.section(routes)
      lines = formatter.result.split("\n").reject(&:empty?)
      plain_lines = lines.map { |l| strip_ansi(l) }
      verb_positions = plain_lines.map { |l| l.index("GET") || l.index("POST") }
      expect(verb_positions.compact.uniq.size).to eq(1)
    end
  end

  describe "per-group column widths" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "computes independent column widths per group" do
      routes = [
        {name: "short", verb: "GET", path: "/short", reqs: "a#index"},
        {name: "a_very_long_prefix_that_exceeds_everything", verb: "GET", path: "/very/long/path/here", reqs: "b#index"}
      ]
      formatter.section(routes)
      result = strip_ansi(formatter.result)
      lines = result.split("\n").reject(&:empty?)
      # Group "a" should have short prefix width, group "b" should have its own
      a_lines = lines.select { |l| l.include?("/short") }
      b_lines = lines.select { |l| l.include?("/very/long") }
      expect(a_lines).not_to be_empty
      expect(b_lines).not_to be_empty
    end
  end

  describe "GROUP feature" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "groups by controller when GROUP=controller" do
      ENV["GROUP"] = "controller"
      routes = [
        {name: "users", verb: "GET", path: "/users", reqs: "users#index"},
        {name: "posts", verb: "GET", path: "/posts", reqs: "posts#index"},
        {name: "", verb: "POST", path: "/users", reqs: "users#create"}
      ]
      formatter.section(routes)
      result = strip_ansi(formatter.result)
      expect(result).to include("── users ──")
      expect(result).to include("── posts ──")
    end

    it "groups by verb when GROUP=verb" do
      ENV["GROUP"] = "verb"
      routes = [
        {name: "users", verb: "GET", path: "/users", reqs: "users#index"},
        {name: "", verb: "POST", path: "/users", reqs: "users#create"}
      ]
      formatter.section(routes)
      result = strip_ansi(formatter.result)
      expect(result).to include("── GET ──")
      expect(result).to include("── POST ──")
    end
  end

  describe "HELP feature" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "shows help text when HELP=1" do
      ENV["HELP"] = "1"
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).to include("Railbow Routes Options")
      expect(result).to include("GROUP=controller")
      expect(result).to include("GROUP=none")
      expect(result).to include("COMPACT")
      expect(result).to include("PLAIN=1")
    end
  end

  describe "plain mode (formatting disabled)" do
    before { allow($stdout).to receive(:tty?).and_return(true) }

    it "falls back to Rails output when PLAIN=1" do
      ENV["PLAIN"] = "1"
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).not_to include("\e[")
      expect(result).to include("Prefix")
    end

    it "falls back to Rails output when NO_COLOR is set" do
      ENV["NO_COLOR"] = ""
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).not_to include("\e[")
    end

    it "falls back to Rails output when CLAUDECODE is set" do
      ENV["CLAUDECODE"] = "1"
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).not_to include("\e[")
    end

    it "falls back to Rails output when CI is set" do
      ENV["CI"] = "true"
      formatter.section(sample_routes)
      result = formatter.result
      expect(result).not_to include("\e[")
    end
  end
end
