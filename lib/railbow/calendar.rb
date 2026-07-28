# frozen_string_literal: true

require "date"

module Railbow
  # Turns an ordered list of migration versions into the calendar furniture that
  # gives the status table its shape: a separator row when the month changes,
  # optionally one when the ISO week changes, and optionally a tick mark on the
  # date column at each week boundary.
  #
  # A separator introduces the rows beneath it and runs until the next separator,
  # so the optional count always answers "how many migrations in this section".
  module Calendar
    DEFAULT_MONTH_LABEL = "%b %Y   W%V"
    # Week rows carry the month too, so the week number sits at the same offset
    # on every separator row rather than jumping left when the month is absent.
    DEFAULT_WEEK_LABEL = DEFAULT_MONTH_LABEL

    # What the renderer needs to draw the calendar: a label per separator row,
    # and which rows open a week (for tick marks). Both keyed by row index.
    class Furniture
      attr_reader :separators, :tick_rows

      def initialize
        @separators = {}
        @tick_rows = Set.new
      end
    end

    module_function

    def none
      Furniture.new
    end

    def build(versions, weeks: false, ticks: false, counts: false,
      month_label: DEFAULT_MONTH_LABEL, week_label: DEFAULT_WEEK_LABEL)
      dates = versions.map { |v| parse_date(v) }
      furniture = none

      dates.each_with_index do |date, i|
        prev = (i > 0) ? dates[i - 1] : nil
        next unless date && prev

        opens_week = week_key(prev) != week_key(date)

        if month_key(prev) != month_key(date)
          furniture.separators[i] = date.strftime(month_label)
        elsif weeks && opens_week
          furniture.separators[i] = date.strftime(week_label)
        end

        furniture.tick_rows << i if ticks && opens_week
      end

      append_counts(furniture.separators, dates.size) if counts
      furniture
    end

    def parse_date(version)
      v = version.to_s
      Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i)
    rescue Date::Error
      nil
    end

    def month_key(date)
      [date.year, date.month]
    end

    # cwyear, not year: the ISO week of Jan 1 can belong to the year before.
    def week_key(date)
      [date.cwyear, date.cweek]
    end

    def append_counts(separators, total)
      indices = separators.keys.sort
      indices.each_with_index do |index, nth|
        section_end = indices[nth + 1] || total
        separators[index] = "#{separators[index]} · #{migration_count(section_end - index)}"
      end
    end

    # Spelled out: a bare number next to a week label reads as part of the date.
    def migration_count(count)
      "#{count} #{(count == 1) ? "migration" : "migrations"}"
    end
  end
end
