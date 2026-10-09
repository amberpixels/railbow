# frozen_string_literal: true

require "date"

module Railbow
  # The clock railbow shows times on. Migration IDs and git dates are fixed
  # moments; RBW_TZ (or `tz:` in .railbow.yml) only picks the zone they are
  # shown in: "local" (the default), "utc", or any zone name Rails accepts,
  # e.g. "America/New_York" or "Eastern Time (US & Canada)".
  module Clock
    @zones = {}

    module_function

    # A migration ID is the UTC time the migration was generated, which is
    # how Rails names them. Returns nil for anything that is not one.
    def from_version(version)
      v = version.to_s
      return nil unless v.match?(/\A\d{14}\z/)

      utc = Time.utc(
        v[0..3].to_i, v[4..5].to_i, v[6..7].to_i,
        v[8..9].to_i, v[10..11].to_i, v[12..13].to_i
      )
      in_zone(utc)
    rescue ArgumentError
      nil
    end

    def in_zone(time)
      case (z = zone)
      when :local then time.getlocal
      when :utc then time.getutc
      else time.in_time_zone(z)
      end
    end

    def today
      in_zone(Time.now).to_date
    end

    # The migration ID of the midnight that starts date on this clock, so a
    # day-based window can be compared against migration IDs directly.
    def version_at(date)
      start = case (z = zone)
      when :local then Time.local(date.year, date.month, date.day)
      when :utc then Time.utc(date.year, date.month, date.day)
      else z.local(date.year, date.month, date.day)
      end
      start.utc.strftime("%Y%m%d%H%M%S")
    end

    def zone
      name = Params.tz
      @zones[name] ||= resolve(name)
    end

    def resolve(name)
      case name.downcase
      when "local" then :local
      when "utc" then :utc
      else
        require "active_support"
        require "active_support/time"
        ActiveSupport::TimeZone[name] || begin
          warn "  Warning: unrecognized RBW_TZ=#{name}, showing local time"
          :local
        end
      end
    end
  end
end
