# frozen_string_literal: true

require_relative "../logo"

module Railbow
  module Status
    module Help
      module_function

      def print
        Railbow.print_logo
        puts <<~HELP

          Enhanced db:migrate:status

          \e[1mUsage:\e[0m
            [RBW_*=value ...] rake db:migrate:status

          \e[1mOptions:\e[0m
            RBW_SINCE=<period>       Filter migrations by age (default: all)
                                     Values: all, 2mo, 1w, 30d, 1y, etc.
                                     Units: d (days), w (weeks), mo/m (months), y (years)

            RBW_SINCE_MIN=<n>        Never show fewer than n migrations, however
                                     old (default: 10). The window above is a
                                     soft limit: a database with five migrations
                                     shows all five rather than reporting an
                                     empty period. 0 disables the floor.

            RBW_DATE=<mode>          Date column format (default: full):
                                     full       - 2026-01-30 12:08:54 (column: Created At)
                                     rel        - ~3d ago
                                     short      - Jan 30 (column: Date)
                                     custom(…)  - user strftime, e.g. custom(%b %d, %Y)

            RBW_VIEW=<options>       Display options (comma-separated):
                                     calendar   - show month/year separator lines + week ticks
                                     tables     - parse migration files, show Tables column

            RBW_COMPACT=<options>    Compact display (comma-separated):
                                     oneline    - truncate instead of wrapping
                                     dense      - remove cell padding
                                     noheader   - hide table header row
                                     maxw:<n>   - cap column widths at n chars
                                     hide:<col> - hide a column by name (repeatable)

            RBW_CALENDAR=<options>   Calendar sub-options (requires RBW_VIEW=calendar):
                                     (empty)      - month separators only, no week
                                                    markers at all
                                     wticks       - week tick marks on the date column
                                     wdividers    - a separator row per ISO week
                                     counts       - append "· N migrations" to every
                                                    separator row (that section)
                                     label:<fmt>  - strftime for month separators
                                                    (default: %b %Y   W%V)
                                     wlabel:<fmt> - strftime for week separators
                                                    (default: same as label, so the
                                                    week number never shifts)

            RBW_DB=<options>         Multi-database runs (default: focus).
                                     An empty value expands every database into
                                     its own section, in database.yml order,
                                     with column widths shared so the tables
                                     line up. Databases sharing a migrations
                                     path (shards) merge into one table with a
                                     status per database.
                                     focus        - expand only the first
                                                    database, summarizing the
                                                    rest in a line each. A
                                                    database with migrations
                                                    pending is always expanded
                                     only:<name>  - render only this database
                                                    (repeatable)
                                     skip:<name>  - drop this database
                                                    (repeatable)
                                     full         - draw every database in full,
                                                    overriding focus and never
                                                    collapsing a quiet one
                                     inline       - one merged table ordered by
                                                    version, with a Db column

            RBW_GIT=<options>        Git integration (comma-separated):
                                     author     - add an Author column (same as author:all)
                                     author:all - add an Author column
                                     author:me  - highlight your own migrations
                                     diff       - tag migrations by git origin
                                     base:<branch> - base branch for diff (default: auto-detected)
                                     mask:<re>  - regex to extract branch label
                                                  e.g. mask:(PS-[^/]+)/
                                     mask:auto  - auto-extract ticket id from branch name

            RBW_PLAIN=1              Disable Railbow formatting (plain Rails output)

            RBW_FORCE=1              Force Railbow formatting even when piped, in CI,
                                     or called by an LLM agent (RBW_PLAIN=1 still wins)

            RBW_HELP=1               Show this help message

          \e[2mAuto-disabled when piped, in CI, or when called by an LLM agent.\e[0m

          \e[1mExamples:\e[0m
            rake db:migrate:status
            RBW_SINCE=2mo RBW_VIEW=calendar rake db:migrate:status
            RBW_CALENDAR=wdividers,counts rake db:migrate:status
            RBW_VIEW=tables RBW_GIT=author rake db:migrate:status
            RBW_GIT=author:me RBW_SINCE=3mo rake db:migrate:status
            RBW_DATE=rel rake db:migrate:status
            RBW_DATE=short rake db:migrate:status
            RBW_DATE='custom(%b %d, %Y)' rake db:migrate:status
            RBW_GIT=diff rake db:migrate:status
            RBW_GIT=diff,base:develop rake db:migrate:status
            RBW_GIT=diff,mask:(PS-[^/]+)/ rake db:migrate:status
            RBW_DB= rake db:migrate:status
            RBW_DB=only:primary rake db:migrate:status
            RBW_DB=inline rake db:migrate:status

        HELP
      end
    end
  end
end
