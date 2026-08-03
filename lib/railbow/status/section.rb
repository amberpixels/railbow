# frozen_string_literal: true

require "date"
require_relative "../config"
require_relative "../formatters/base"
require_relative "../migration_parser"
require_relative "../params"
require_relative "../table"
require_relative "../calendar"
require_relative "git_data"
require_relative "ghosts"

module Railbow
  module Status
    # One migrations directory's worth of db:migrate:status.
    #
    # Usually that is one database. Databases sharing a migrations_paths (the
    # shape horizontal sharding takes) see the same files and differ only in
    # what they have applied, so they merge into a single section carrying a
    # status per database.
    #
    # Rows are built lazily, on first read, because merging has to finish
    # before the status cells can be built. A section never prints: Printer
    # owns output, which is what lets sections share column widths.
    class Section
      # Index of the Date column, where calendar week ticks are drawn.
      TICK_COL = 2

      # Width the Migration Name column is capped at once anything competes
      # with it for horizontal space (tags, authors, table names).
      NAME_COL_WIDTH = 60

      # Floor the width budget may shrink the name column down to on a narrow
      # terminal, before it starts dropping columns instead.
      NAME_COL_MIN_WIDTH = 24

      NO_FILE = "NO FILE"

      # A version one database in a shard group has and another does not.
      ABSENT = "·"

      attr_reader :databases, :migrations_key, :state, :hidden_count, :total_count,
        :since_value, :entries, :ghosts

      # True when the time window left too few rows and the floor topped the
      # section back up, which is worth saying out loud: the table then shows
      # migrations from outside the window it advertises.
      def floor_applied?
        @floor_applied == true
      end

      def initialize(pool)
        @formatter = Formatters::Base.new
        @databases = [{name: pool.db_config.name, database: pool.db_config.database}]
        @migrations_key = migrations_key_for(pool)
        @entries = {}
        @ghosts = {}
        @hidden_count = 0
        @total_count = 0
        @window_count = 0
        @floor_applied = false
        @since_value = Railbow::Params.since

        collect(pool)
      end

      # The database this section is named after. Multi-database sections use
      # #databases; this is the single-database convenience.
      def database
        databases.first[:database]
      end

      def db_name
        databases.first[:name]
      end

      def db_names
        databases.map { |d| d[:name] }
      end

      def same_migrations?(other)
        migrations_key == other.migrations_key
      end

      # Folds another database that runs the same migration files into this
      # section: its statuses join the existing rows, its identity joins the
      # header, and anything already built is discarded.
      def merge!(other)
        other.entries.each do |version, entry|
          mine = (@entries[version] ||= {name: entry[:name], statuses: {}})
          mine[:name] = entry[:name] if mine[:name].include?(NO_FILE)
          mine[:statuses].merge!(entry[:statuses])
        end
        @databases.concat(other.databases)
        @ghosts = other.ghosts.merge(@ghosts)
        @total_count = [@total_count, other.total_count].max
        @hidden_count = [@hidden_count, other.hidden_count].max
        @pending_count = [pending_count, other.pending_count].max
        @ghost_total = [ghost_count, other.ghost_count].max
        @latest_applied_version = [latest_applied_version, other.latest_applied_version].compact.max
        @state = other.state if state_rank(other.state) > state_rank(@state)
        reset_built
        self
      end

      def sharded?
        databases.size > 1
      end

      # Whether any row this section would render is still pending. Answered
      # from the collected entries, so asking costs no git work - which is the
      # point, since it is asked in order to decide whether to build the rows
      # at all.
      def pending_in_view?
        entries.any? { |_, entry| entry[:statuses].value?("down") }
      end

      def tick_col
        TICK_COL
      end

      # Nothing in the window and nothing pending: the section has no table
      # worth drawing, only a line saying so.
      def quiet?
        state != :ok
      end

      def pending_count
        @pending_count ||= 0
      end

      def ghost_count
        @ghost_total ||= 0
      end

      attr_reader :latest_applied_version

      def latest_applied_date
        version_date(latest_applied_version) if latest_applied_version
      end

      def columns
        build! unless @built
        @columns
      end

      def rows
        build! unless @built
        @rows
      end

      def highlight_rows
        build! unless @built
        @highlight_rows
      end

      def ghost_rows
        build! unless @built
        @ghost_rows
      end

      def down_rows
        build! unless @built
        @down_rows
      end

      def calendar
        build! unless @built
        @calendar
      end

      private

      attr_reader :formatter, :git, :version_to_file

      def migrations_key_for(pool)
        paths = Array(pool.migration_context.migrations_paths)
        paths.map { |p| File.expand_path(p.to_s) }.sort
      end

      def state_rank(state)
        {no_migrations: 0, none_in_period: 1, ok: 2}.fetch(state, 0)
      end

      def reset_built
        @built = false
      end

      def collect(pool)
        db_list = pool.migration_context.migrations_status
        @total_count = db_list.size
        record_totals(db_list)

        if db_list.empty?
          @state = :no_migrations
          return
        end

        db_list = apply_since_filter(db_list)

        # State tracks recency, not row count: a section whose only rows were
        # pulled in by the floor still has nothing recent to say, and should
        # still collapse in a multi-database run.
        @state = @window_count.zero? ? :none_in_period : :ok
        return if db_list.empty?

        @entries = db_list.to_h do |status, version, name|
          [version.to_s, {name: name, statuses: {db_name => status}}]
        end

        @version_to_file = {}
        pool.migration_context.migrations.each do |m|
          @version_to_file[m.version.to_s] = m.filename
        end
      end

      # Counted over every migration, not just the ones in the window, so a
      # collapsed section can still report what it is hiding.
      def record_totals(db_list)
        @pending_count = db_list.count { |status, _, _| status == "down" }
        @ghost_total = db_list.count { |_, _, name| name.to_s.include?(NO_FILE) }
        applied = db_list.select { |status, _, _| status == "up" }
        @latest_applied_version = applied.last&.dig(1)&.to_s
      end

      # The time window is a soft limit. Whatever it leaves, the floor tops the
      # result back up to RBW_SINCE_MIN rows, so a database with five
      # migrations shows all five rather than hiding the two that happen to be
      # old. The window is still what decides whether the section reads as
      # recent - see #collect.
      def apply_since_filter(db_list)
        since_cutoff = Railbow::Params.parse_since(since_value, context: "migrations")
        unless since_cutoff
          @window_count = db_list.size
          return db_list
        end

        cutoff_version = since_cutoff.strftime("%Y%m%d%H%M%S").to_i
        @window_count = db_list.count { |_, v, _| v.to_i >= cutoff_version }

        # Not Comparable#clamp: the floor can exceed the total, and clamp
        # raises when its lower bound sits above its upper one.
        keep = [@window_count, floor].max
        keep = db_list.size if keep > db_list.size
        @floor_applied = keep > @window_count
        if keep.zero?
          @hidden_count = db_list.size
          return []
        end

        # Taken by rank rather than by slicing the tail, so the same rows are
        # kept whatever order Rails hands the list over in.
        threshold = db_list.map { |_, v, _| v.to_i }.sort[-keep]
        filtered = db_list.select { |_, v, _| v.to_i >= threshold }
        @hidden_count = db_list.size - filtered.size
        filtered
      end

      def floor
        [Railbow::Params.since_min, 0].max
      end

      def load_git
        sample_file = version_to_file.values.first
        GitData.for(
          migrate_dir: sample_file ? File.dirname(sample_file) : nil,
          author_enabled: author_enabled?,
          diff_enabled: Railbow::Params.git_diff?,
          base_override: Railbow::Params.git_base,
          branch_mask: Railbow::Params.git_mask
        )
      end

      def load_ghosts
        return {} unless Ghosts.available?

        versions = entries.select { |_, e| e[:name].include?(NO_FILE) }.keys
        return {} if versions.empty?

        Ghosts.load(versions, with_content: tables_enabled?)
      end

      def author_mode
        @author_mode ||= Railbow::Params.git_author
      end

      def author_enabled?
        %w[all me].include?(author_mode)
      end

      def tables_enabled?
        return @tables_enabled unless @tables_enabled.nil?

        @tables_enabled = Railbow::Params.view_tables?
      end

      # Git lookups and ghost recovery happen here rather than during collect,
      # so a section that ends up collapsed never pays for them.
      def build!
        @built = true
        @columns = []
        @rows = []
        @highlight_rows = Set.new
        @ghost_rows = Set.new
        @down_rows = Set.new
        @calendar = Railbow::Calendar.none
        return if entries.empty?

        @git = load_git
        @ghosts = load_ghosts
        @columns = build_columns
        @rows = build_rows
        @calendar = build_calendar
      end

      # The name column only needs capping when something else competes for the
      # row: table tags, an author column, branch badges or landed badges.
      #
      # On a terminal too narrow for the full row the width budget degrades the
      # table instead of letting it wrap: the name column shrinks first, then
      # Tables is dropped, then the formatted date (the raw Migration ID keeps
      # the timestamp), then Who.
      def build_columns
        @name_col_width = needs_name_truncation? ? NAME_COL_WIDTH : nil

        cols = [
          Table::Column.new(label: "Status", max_width: status_col_width,
            sticky: true, accent: true, aliased: !sharded?),
          Table::Column.new(label: "Migration ID", sticky: true),
          Table::Column.new(label: (date_format == "full") ? "Created At" : "Date",
            droppable: 2),
          Table::Column.new(label: "Migration Name",
            max_width: @name_col_width,
            truncate: !@name_col_width.nil?,
            shrinkable: true, shrink_floor: NAME_COL_MIN_WIDTH)
        ]
        cols << Table::Column.new(label: "Who", droppable: 3) if author_mode == "all"
        if tables_enabled?
          truncate_fn = ->(cell_raw, max_w) { formatter.table_tags_fitted(cell_raw, max_w) }
          cols << Table::Column.new(label: "Tables", droppable: 1,
            truncate: Railbow::Params.compact_oneline?, truncate_fn: truncate_fn)
        end
        cols
      end

      # One glyph plus a space per database, and never narrower than the single
      # database case, which also has to fit a trailing indicator.
      def status_col_width
        [6, 3 * databases.size].max
      end

      def date_format
        @date_format ||= Railbow::Params.date_format
      end

      def needs_name_truncation?
        tables_enabled? || author_mode == "all" || Railbow::Params.git_diff? || landed_tags?
      end

      # Only migrations that landed well after they were written earn a badge,
      # so a repo that always merges promptly never pays for the column space.
      def landed_tags?
        git.landed_dates.any? do |basename, landed|
          mig_date = version_date(basename[0..13])
          mig_date && (landed - mig_date) > 7
        end
      end

      def build_rows
        versions = entries.keys.sort
        latest_mig_date = version_date(versions.last)
        author_display = build_author_display

        versions.each_with_index.map do |version, idx|
          entry = entries[version]
          name = entry[:name]
          statuses = entry[:statuses]

          # A pending migration is not in effect yet: grey the whole row out so
          # it reads as inactive next to the applied ones. In a shard group only
          # a row pending everywhere reads as inactive.
          @down_rows << idx if statuses.values.all? { |s| s == "down" }

          ghost = name.include?(NO_FILE) ? ghosts[version] : nil
          @ghost_rows << idx if ghost

          status_cell = build_status_cell(statuses, ghost)
          display_name = name_cell(
            name: name, version: version, ghost: ghost, latest_mig_date: latest_mig_date
          ) do |indicator|
            status_cell = "#{status_cell} #{indicator}"
          end

          row = [status_cell, version, formatter.format_date(version, date_format), display_name]
          row << author_cell(version, ghost, author_display) if author_mode == "all"
          track_highlight(idx, version, ghost) if author_enabled?
          row << formatter.table_tags(tables_for(version, ghost)) if tables_enabled?
          row
        end
      end

      def build_status_cell(statuses, ghost)
        return status_glyph(statuses[db_name], ghost) unless sharded?

        databases.map { |db| status_glyph(statuses[db[:name]], ghost) }.join(" ")
      end

      # A sharded section resolves the up/down aliases itself: the renderer
      # applies them by matching the whole cell, which a cluster never is.
      def status_glyph(status, ghost)
        # A superseded ghost lives on under another version: stale bookkeeping,
        # not a lost migration, so it gets a calmer glyph.
        return ghost.superseded_by ? "🪦" : "👻" if ghost && status

        case status
        when "up" then formatter.green_bold(sharded? ? status_alias("up") : "up")
        when "down" then formatter.yellow_bold(sharded? ? status_alias("down") : "down")
        when nil then formatter.dim(ABSENT)
        else status
        end
      end

      def status_alias(status)
        @status_aliases ||= Railbow::Config.value_aliases["Status"] || {}
        @status_aliases[status] || status
      end

      # Builds the Migration Name cell and right-aligns whatever badges it
      # carries. Yields a status indicator when the row earns one.
      def name_cell(name:, version:, ghost:, latest_mig_date:)
        if ghost
          return with_tags(Ghosts.display_name(ghost), Ghosts.tag(ghost), strip: false)
        end
        return formatter.red(NO_FILE) if name.include?(NO_FILE)

        basename = basename_for(version)
        tags = []

        diff_tag = nil
        if Railbow::Params.git_diff? && basename
          if git.incoming_merge_files.include?(basename)
            yield "\e[38;5;213m⬇#{Formatters::Base::RESET}"
            diff_tag = formatter.diff_tag_merging(git.merge_source_label || "merge")
          elsif git.uncommitted_files.include?(basename)
            yield "\e[38;5;220m◆#{Formatters::Base::RESET}"
          end
          diff_tag ||= formatter.diff_tag_branch(git.branch_origins[basename]) if git.branch_origins.key?(basename)
        end

        tags << landed_tag(basename, version, latest_mig_date)
        tags << diff_tag

        with_tags(name, tags.compact.join(" "))
      end

      # Landed badge: the migration reached the mainline more than a week after
      # it was written, which usually means a long-lived branch.
      def landed_tag(basename, version, latest_mig_date)
        return nil unless basename

        landed = git.landed_dates[basename]
        return nil unless landed

        mig_date = version_date(version)
        return nil unless mig_date && (landed - mig_date) > 7

        formatter.landed_tag(landed, fresh: latest_mig_date && landed >= latest_mig_date)
      end

      # Pads the name so its tags sit flush against the right edge of the
      # column. Falls back to a two-space gap when the column is uncapped.
      def with_tags(name, tags, strip: true)
        return name if tags.nil? || tags.empty?
        return "#{name}  #{tags}" unless @name_col_width

        tags_width = formatter.display_width(formatter.strip_ansi(tags))
        name = formatter.truncate_str(name, @name_col_width - tags_width - 2)
        name_width = formatter.display_width(strip ? formatter.strip_ansi(name) : name)
        padding = @name_col_width - name_width - tags_width
        "#{name}#{" " * [padding, 2].max}#{tags}"
      end

      def build_author_display
        return {} unless author_mode == "all"

        raw = git.author_names.values.compact
        raw << git.git_name if git.git_name
        ghosts.each_value { |g| raw << g.author_name if g.author_name }
        Railbow::Params.format_authors(raw)
      end

      def author_cell(version, ghost, author_display)
        raw = if ghost
          ghost.author_name || ""
        else
          basename = basename_for(version)
          author = basename ? git.author_names[basename] : nil
          author || (basename ? git.git_name : "")
        end
        author_display[raw] || Railbow::Params.format_author(raw)
      end

      # Uncommitted migrations have no git author, so they are treated as mine.
      # Match by email first, then by name, to survive a commit email that
      # differs from git config (GitHub noreply addresses after a squash-merge,
      # or a mailmap rewrite).
      def track_highlight(idx, version, ghost)
        return unless git.git_email

        if ghost
          email = ghost.author_email&.downcase
          @highlight_rows << idx if email && email == git.git_email
          return
        end

        basename = basename_for(version)
        # A row with no file has no author to compare against, which the two
        # modes read differently: author:all treats "nobody else's" as mine,
        # author:me requires a real file before claiming anything.
        return if author_mode == "me" && basename.nil?

        email = git.author_emails[basename]
        author = git.author_names[basename]
        @highlight_rows << idx if email.nil? || email == git.git_email ||
          (git.git_name && author && author.downcase == git.git_name.downcase)
      end

      def tables_for(version, ghost)
        if ghost&.content && !ghost.content.empty?
          Railbow::MigrationParser.extract_tables_from_content(ghost.content)
        else
          Railbow::MigrationParser.extract_tables(version_to_file[version])
        end
      end

      def basename_for(version)
        filepath = version_to_file[version]
        filepath ? File.basename(filepath) : nil
      end

      def build_calendar
        return Railbow::Calendar.none unless Railbow::Params.view_calendar?

        Railbow::Calendar.build(
          entries.keys.sort,
          weeks: Railbow::Params.calendar_wdividers?,
          ticks: Railbow::Params.calendar_wticks?,
          counts: Railbow::Params.calendar_counts?,
          month_label: Railbow::Params.calendar_label,
          week_label: Railbow::Params.calendar_week_label
        )
      end

      def version_date(version)
        v = version.to_s
        Date.new(v[0..3].to_i, v[4..5].to_i, v[6..7].to_i)
      rescue Date::Error
        nil
      end
    end
  end
end
