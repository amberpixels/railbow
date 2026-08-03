# frozen_string_literal: true

require_relative "../calendar"
require_relative "../color_assigner"
require_relative "../config"
require_relative "../formatters/base"
require_relative "../params"
require_relative "../table"

module Railbow
  module Status
    # Turns collected sections into output. The only place db:migrate:status
    # writes to stdout, which is what lets a multi-database run share column
    # widths and print a single header.
    #
    # A run holding one database renders exactly as it did before multi-database
    # support existed: no overview line, no section rule, nothing new.
    class Printer
      RULE = "─"
      COLLAPSED = "⋯"
      PURPLE = Table::Themes::PURPLE
      RESET = Formatters::Base::RESET

      DEFAULT_RULE_WIDTH = 60

      def initialize(sections, skipped: [])
        @sections = Array(sections)
        @skipped = skipped
        @formatter = Formatters::Base.new
      end

      def print
        return print_solo(sections.first) if solo?

        print_overview
        Railbow::Params.db_inline? ? print_inline : print_sections
        print_skipped
      end

      private

      attr_reader :sections, :skipped, :formatter

      def print_sections
        widths = shared_widths
        sections.each { |section| print_grouped(section, widths) }
      end

      # Tables open with a blank line of their own. A collapsed line only needs
      # one when it follows a table, so a run of quiet databases reads as one
      # block instead of a ladder of gaps.
      def print_grouped(section, widths)
        if collapse?(section)
          puts if @last_was_table
          puts collapsed_line(section)
          @last_was_table = false
        else
          print_table_section(section, widths)
          @last_was_table = true
        end
      end

      # One database, one migrations path: the shape every single-database app
      # has, and the one whose output must not move.
      def solo?
        sections.size == 1 && !sections.first.sharded? && skipped.empty?
      end

      def print_solo(section)
        puts "\n#{formatter.emoji(:status)} Database: #{formatter.cyan(section.database)}"
        puts

        if section.state == :no_migrations
          puts formatter.yellow("  No migrations found")
          return
        end

        if (note = hidden_note(section))
          puts note
          puts
        end

        if section.rows.empty?
          puts formatter.yellow("  No migrations in the selected period")
          return
        end

        puts render_table(section)
      end

      # Says what the window hid, and admits when the floor overrode it: the
      # table then holds rows older than the window it names, and a bare
      # "hidden - SINCE=70d" would read as a contradiction next to them.
      def hidden_note(section)
        return nil unless section.hidden_count > 0

        note = "(#{section.hidden_count} older migrations hidden - SINCE=#{section.since_value}"
        note += ", showing the last #{section.rows.size}" if section.floor_applied?
        formatter.dim("  #{note})")
      end

      def print_overview
        names = sections.flat_map(&:db_names)
        puts "\n#{formatter.emoji(:status)} #{count_label(names.size, "database")} " \
             "#{formatter.dim("·")} #{formatter.cyan(names.join(", "))}"
      end

      def print_table_section(section, widths)
        renderer = renderer_for(section, widths)
        puts
        puts section_header(section, renderer.fixed_width(widths))

        # Reachable with RBW_DB=full, which asks for every section to be drawn
        # in full, including the ones that would otherwise have collapsed.
        if section.state == :no_migrations
          puts formatter.yellow("  No migrations found")
          return
        elsif section.rows.empty?
          puts formatter.yellow("  No migrations in the selected period")
          return
        end

        puts render_table(section, renderer)
      end

      # RBW_DB=inline: every database in one time-ordered table, each row
      # carrying a Db badge. The calendar then spans the whole application
      # rather than restarting per database, which is the point of asking for
      # it. Quiet databases still collapse below the table.
      def print_inline
        live = sections.reject { |s| collapse?(s) || s.rows.empty? }
        collapsed = sections - live

        if live.any?
          entries = inline_entries(live)
          calendar = inline_calendar(entries)
          puts
          puts inline_renderer(live.first).render(
            entries.map { |e| e[:row] },
            separators: calendar.separators,
            highlight_rows: inline_marked(entries, :highlight_rows),
            ghost_rows: inline_marked(entries, :ghost_rows),
            dim_rows: inline_marked(entries, :down_rows),
            tick_rows: calendar.tick_rows,
            tick_col: live.first.tick_col + 1
          )
        end

        collapsed.each { |section| puts collapsed_line(section) }
      end

      # Sorted by version, so the databases interleave by when each migration
      # was written. Ties fall back to config order, which keeps two databases
      # that share a timestamp in database.yml order rather than an arbitrary one.
      def inline_entries(live)
        assigner = Railbow::ColorAssigner.new(live.map { |s| inline_label(s) })

        entries = live.each_with_index.flat_map do |section, order|
          badge = "#{assigner.color_for(inline_label(section))}● #{inline_label(section)}#{RESET}"
          section.rows.each_with_index.map do |row, index|
            {version: row[1].to_s, order: order, section: section, index: index,
             row: [row[0], badge, *row[1..]]}
          end
        end

        entries.sort_by { |e| [e[:version], e[:order]] }
      end

      def inline_label(section)
        section.db_names.join("+")
      end

      def inline_renderer(section)
        columns = section.columns.dup
        columns.insert(1, Table::Column.new(label: "Db", sticky: true))

        Table::Renderer.new(
          columns: columns,
          theme: Table::Themes::WALLS,
          compact: Railbow::Params.compact_options,
          aliases: Railbow::Config.table_aliases
        )
      end

      # Row markers are per-section indices; re-key them to the merged order.
      def inline_marked(entries, kind)
        marked = Set.new
        entries.each_with_index do |entry, i|
          marked << i if entry[:section].public_send(kind).include?(entry[:index])
        end
        marked
      end

      def inline_calendar(entries)
        Railbow::Calendar.build(
          entries.map { |e| e[:version] },
          weeks: Railbow::Params.calendar_wdividers?,
          ticks: Railbow::Params.calendar_wticks?,
          counts: Railbow::Params.calendar_counts?,
          month_label: Railbow::Params.calendar_label,
          week_label: Railbow::Params.calendar_week_label
        )
      end

      def print_skipped
        return if skipped.empty?

        puts
        puts formatter.dim("#{COLLAPSED} #{count_label(skipped.size, "database")} hidden: #{skipped.join(", ")}")
      end

      # A quiet database says everything it has to say in one line. Nothing in
      # the window means there is no table to draw either, so collapsing loses
      # nothing - the counts below carry what the rows would have shown.
      #
      # RBW_DB=focus collapses the busy ones too, keeping the first database as
      # the one you actually read. Pending migrations veto that: a database
      # with work waiting is drawn in full however focused the run is.
      def collapse?(section)
        return false if Railbow::Params.db_full?
        return true if section.quiet?
        # Focus shapes the sectioned view. Applying it to a merged table would
        # drop every database but the first out of the very thing that exists
        # to hold all of them.
        return false if Railbow::Params.db_inline?
        return false unless Railbow::Params.db_focus?

        !focused?(section) && !section.pending_in_view?
      end

      # The first database in database.yml, which is conventionally primary and
      # is the one Rails migrates first.
      def focused?(section)
        section.equal?(sections.first)
      end

      def collapsed_line(section)
        body = (section.state == :no_migrations) ? "no migrations" : section_summary(section)
        formatter.dim("#{COLLAPSED} #{section.db_names.join(" + ")} · #{body}")
      end

      def section_summary(section)
        parts = [count_label(section.total_count, "migration")]
        parts << ((section.pending_count > 0) ? "#{section.pending_count} pending" : "all applied")
        parts << count_label(section.ghost_count, "ghost") if section.ghost_count > 0

        summary = parts.join(", ")
        if section.pending_count > 0 || section.ghost_count > 0
          "#{summary} outside the #{section.since_value} window - RBW_SINCE=all"
        elsif (date = section.latest_applied_date)
          "#{summary} · latest #{date.strftime("%b %d %Y")}"
        else
          summary
        end
      end

      # "──── primary · pawshop-dev ──── 12 of 240 ────", ruled out to where
      # the last column starts so it frames the table rather than floating.
      def section_header(section, rule_width)
        label = section.db_names.join(" + ")
        detail = section.sharded? ? shared_path(section) : section.database
        head = "#{RULE * 4} #{label} · #{detail} "
        head += "#{RULE * 4} #{shown_count(section)} of #{section.total_count} " if section.hidden_count > 0

        width = (rule_width > 0) ? rule_width : DEFAULT_RULE_WIDTH
        if (term = terminal_width)
          width = [width, term].min
        end
        filler = [width - formatter.display_width(head), 4].max
        "#{PURPLE}#{head}#{RULE * filler}#{RESET}"
      end

      # The rule frames the table, but on a narrow terminal the table itself
      # gives up width, so the rule must never trust fixed_width alone.
      def terminal_width
        return $stdout.winsize[1] if $stdout.respond_to?(:winsize) && $stdout.tty?
        nil
      rescue
        nil
      end

      # A bare "10 of 50" reads as "10 fell inside the window". When the floor
      # overrode the window the selection is a tail rather than a window, so it
      # says "last 10 of 50" - the same words the single-database note uses.
      def shown_count(section)
        shown = section.total_count - section.hidden_count
        section.floor_applied? ? "last #{shown}" : shown.to_s
      end

      # Sharded databases have different database names but one migrations
      # directory, so the directory is what identifies the section.
      def shared_path(section)
        paths = section.migrations_key
        return paths.first.to_s if paths.size <= 1

        paths.map { |p| File.basename(p) }.join(", ")
      end

      # Every section resolves its own widths, then all of them are raised to
      # the per-column maximum so the tables line up with each other.
      def shared_widths
        per_section = sections.reject { |s| collapse?(s) }.map do |section|
          renderer_for(section, nil).column_widths(section.rows)
        end
        return nil if per_section.empty?

        size = per_section.map(&:size).max
        Array.new(size) { |i| per_section.filter_map { |w| w[i] }.max }
      end

      def renderer_for(section, widths)
        Table::Renderer.new(
          columns: section.columns,
          theme: Table::Themes::WALLS,
          compact: Railbow::Params.compact_options,
          aliases: Railbow::Config.table_aliases,
          min_widths: widths
        )
      end

      def render_table(section, renderer = renderer_for(section, nil))
        renderer.render(section.rows,
          separators: section.calendar.separators,
          highlight_rows: section.highlight_rows,
          ghost_rows: section.ghost_rows,
          dim_rows: section.down_rows,
          tick_rows: section.calendar.tick_rows,
          tick_col: section.tick_col)
      end

      def count_label(count, noun)
        "#{count} #{noun}#{"s" unless count == 1}"
      end
    end
  end
end
