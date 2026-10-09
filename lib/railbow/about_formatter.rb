# frozen_string_literal: true

require_relative "formatters/base"

module Railbow
  module AboutFormatter
    TITLE = "About your application's environment"

    def to_s
      return super if Railbow.plain?

      Railbow.guard(-> { super }) { railbow_to_s }
    end

    private

    # Same shape as Rails' own listing (title, then one aligned row per
    # property), with the values styled by what they mean. Properties other
    # gems register render as plain text.
    def railbow_to_s
      f = Formatters::Base.new
      width = properties.map { |(name, _)| name.length }.max.to_i
      lines = [f.bold(TITLE)]

      properties.each do |(name, value)|
        # Lists such as Middleware get a line per item instead of one long run.
        values = Array(value).map { |v| railbow_style_value(f, name, v.to_s) }
        lines << "#{f.bold(name.ljust(width))}   #{values.first}"
        values.drop(1).each { |v| lines << "#{" " * width}   #{v}" }
      end

      lines.join("\n")
    end

    def railbow_style_value(f, name, value)
      case name
      when "Environment" then railbow_style_environment(f, value)
      when "Application root" then f.dim(value)
      when "Database schema version" then railbow_style_schema_version(f, value)
      when /version\z/i then railbow_style_version(f, value)
      else value
      end
    end

    # Production is the one environment worth a jolt.
    def railbow_style_environment(f, value)
      case value
      when "production" then f.bold(f.red(value))
      when "development" then f.green(value)
      else f.yellow(value)
      end
    end

    # The version number takes the accent; anything trailing it, like Ruby's
    # build date and platform, steps back.
    def railbow_style_version(f, value)
      match = value.match(/\d+(?:\.\w+)+/)
      return value unless match

      tail = match.post_match.empty? ? "" : f.dim(match.post_match)
      "#{match.pre_match}#{f.cyan(match[0])}#{tail}"
    end

    # Shown on railbow's clock (RBW_TZ), with the zone named because the
    # digits of the version itself are UTC.
    def railbow_style_schema_version(f, value)
      time = Railbow::Clock.from_version(value)
      return value unless time

      "#{f.cyan(value)}  #{f.dim("(#{time.strftime("%Y-%m-%d %H:%M %Z")}, #{f.format_relative_time_from(time)})")}"
    end
  end
end
