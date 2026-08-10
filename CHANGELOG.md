# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.1] - 2026-08-10

### Fixed

- On a narrow terminal, a migration's branch and landing badges no longer
  vanish from the `db:migrate:status` name column, leaving a stray `...`
  hanging in the padding where they used to sit. The badges are padded flush
  against the right edge of the column, which is exactly where the width
  budget was cutting; the name now gives up the space instead and the badges
  stay put. When a badge is so wide that keeping it would leave under 12
  columns for the name, it is dropped outright rather than squeezing the name
  down to nothing.

## [0.6.0] - 2026-08-03

### Fixed

- On a terminal too narrow for the full `db:migrate:status` row, the table no
  longer wraps mid-cell. A width budget degrades it gracefully instead, one
  sacrifice at a time until the rows fit: the Migration Name column narrows
  first (down to 24 columns), then the Tables column is dropped, then the
  formatted date (the raw Migration ID still carries the timestamp), and as a
  last resort the Who column. Each table gives up only as much as its terminal
  demands, and a wide terminal renders exactly as before.

## [0.5.0] - 2026-07-28

### Added

- Multi-database support for `db:migrate:status`. Rails runs the task once per
  database; railbow now wraps that loop and renders the databases together, as
  one section each in `database.yml` order with column widths shared so the
  tables line up. The section header names the database by its `database.yml`
  name, which is what you configure and filter by, rather than the database
  name Rails reports.
- A database with nothing in the time window and nothing pending collapses to a
  one-line summary instead of an empty table, so the `cache`, `queue` and
  `cable` databases of a stock Rails 8 app stop drowning out your own. Anything
  it hides (pending migrations, ghosts) is counted in the line, along with the
  flag that reveals them.
- Databases sharing a `migrations_paths` (horizontal sharding) merge into a
  single table carrying a status glyph per database, making drift between
  shards visible at a glance. A dim `·` marks a version one shard has never
  seen.
- `RBW_DB` (config key `db`) selects and shapes a multi-database run:
  `only:<name>` and `skip:<name>` (both repeatable) pick databases, `full`
  draws the quiet ones in full, and `inline` merges everything into one table
  ordered by version with a `Db` column, so the calendar spans the whole
  application instead of restarting per database. Filtered-out databases are
  named in a footer rather than silently dropped.

- `RBW_SINCE_MIN` (config key `since_min`, default 10) makes the time window a
  soft limit: whatever `since` leaves, the floor tops it back up to this many
  migrations. A database with five migrations now shows all five rather than
  hiding the two that happen to be old and reporting an empty period. The
  hidden-count line says `showing the last 10` when the floor overrode the
  window, and a multi-database section header reads `last 10 of 50` rather than
  `10 of 50`, so a table holding rows older than the window it names still
  reads honestly in both views. `RBW_SINCE_MIN=0` restores the old hard cutoff.
- `RBW_DB=focus`, **the default**, expands only the first database and
  summarizes the rest in a line each, so a multi-database app is one table to
  read rather than several. A database holding pending migrations is expanded
  anyway: the summary exists to hide what needs no action, and pending work is
  the opposite of that. An empty `RBW_DB` (or `db: ""`) expands every database
  that has recent activity, `full` expands everything including quiet ones, and
  `focus` never applies to an `inline` run, which exists to hold every database
  at once.

### Changed

- Git lookups are now shared across a run: authors, landed dates and branch
  origins are resolved once per migrations directory instead of once per
  database. `RBW_HELP=1` prints the help once for the whole run rather than
  once per database.
- `db:migrate:status` internals moved out of the rake file into
  `Railbow::Status` (`Section`, `Printer`, `GitData`, `Ghosts`, `Help`). No
  output changed: a single-database app renders byte for byte what it did
  before, which a golden fixture now enforces.

## [0.4.0] - 2026-07-28

### Added

- `RBW_CALENDAR=wdividers` gives every ISO week its own separator row, the
  fuller counterpart to `wticks`. A week that opens a new month is left to the
  month row rather than being announced twice. The default stays `wticks`, so
  existing output is unchanged until you opt in.
- `RBW_CALENDAR=counts` appends `· N migrations` to every separator row: how
  many migrations that section holds, counted up to the next separator.
- `RBW_CALENDAR=wlabel:<fmt>` sets the strftime pattern for week rows,
  alongside the existing `label:` for month rows. It defaults to the month
  pattern, so the week number sits at the same offset on every separator row
  rather than shifting left when no new month is announced.
- `railbow demo status` now honors `RBW_CALENDAR`, so the calendar modes can be
  tried without a Rails project.
- An empty `RBW_CALENDAR` (month separators, no week markers) is now documented
  in the help output, the `railbow init` template, and the README. It always
  worked; nobody could have guessed it.

### Changed

- Calendar separator rows are drawn in a muted purple (256-color 97) instead of
  the brighter 141, so they frame the migrations without competing with them.
- Migrations that are not applied (`down`) now render as a greyed-out row in
  `db:migrate:status`, instead of signalling their state through the status
  column alone. The row keeps its layout and its status glyph keeps its color;
  everything else drops its own colors, so pending migrations read as inactive
  next to the applied ones.

### Fixed

- Rows whose last column wrapped were indented with too wide a blank prefix:
  building the row mutated the very cell that the wrapped-line indent is
  measured from. Reachable from `routes`, `about`, and `stats`.
- A separator label wider than its column no longer pushes the rest of the row
  sideways. Separator rows are drawn as empty walls with the label laid over
  them, so a long label spills into the blank space to its right.
- `RBW_HELP` output for `db:migrate:status` uses plain hyphens instead of
  em-dashes, matching the rest of the user-facing text.

## [0.3.0] - 2026-07-23

### Added

- Ghost rows in `db:migrate:status` now surface mighost 0.5's classification:
  a superseded ghost (re-timestamped migration) shows a calmer 🪦 status with
  a `≡ <version>` badge pointing at its successor, and a ghost deleted with no
  surviving branch shows `✂ deleted in:<sha>`. Branch badges are unchanged and
  take precedence right after supersession.
- `RBW_FORCE=1` forces Railbow formatting past every auto-detection
  (`NO_COLOR`, CI, piped output, LLM agent detection). An explicit
  `RBW_PLAIN=1` still wins.

### Changed

- Ghost data now comes from `Mighost::API.orphaned_migrations`, so
  `db:migrate:status` honors mighost dismissals and `hide_superseded` for the
  first time: a dismissed or hidden ghost renders as plain `NO FILE` instead
  of 👻. Live git/worktree recovery still kicks in for versions without a
  stored snapshot, so fresh clones keep working with zero setup.

### Fixed

- A ghost row without a branch no longer inherits the previous ghost row's
  branch badge (a stale local leaked across loop iterations; unreachable
  before mighost 0.5 made branchless ghosts the normal case).

## [0.2.0] - 2026-07-23

### Added

- Affected-table detection now recognizes tables passed via keyword
  arguments (`table:`, `to_table:`, `from_table:`), covering project-level
  migration helpers and DSLs that the ActiveRecord method allow-list missed.
- `change_column_default` and `change_column_null` are recognized, and
  foreign-key methods contribute their first table even when the target is
  given as `to_table:`.

### Fixed

- Ruby comments no longer produce phantom tables: content is stripped of
  `#` comments (preserving `#{}` interpolation) before scanning, so a
  comment mentioning `ALTER TABLE` or a commented-out `create_table` does
  not count.

### Changed

- Ghost recovery integration targets [mighost](https://github.com/amberpixels/mighost)
  0.5, which classifies superseded ghosts and reports accurate branch
  attribution.

## [0.1.0] - 2026-07-08

First public release.

### Added

- Colorful `db:migrate` / `db:migrate:down` output with readable millisecond
  timing.
- Rich `db:migrate:status` dashboard: calendar view with month/week
  separators, status aliases, created-at timestamps, landing-date badges,
  branch badges, affected-table detection, time filtering, and highlighting
  of your own migrations.
- Git integration: authors, diffs, branch origin, landing dates, and
  uncommitted-file indicators.
- Ghost migration recovery in `db:migrate:status` via the optional
  [mighost](https://github.com/amberpixels/mighost) gem (`Mighost::API`).
- Color-coded `rails routes`, `rails stats` tables, `rails notes` with git
  blame, and polished `rails about`.
- Layered configuration: built-in defaults, `~/.config/railbow/config.yml`,
  `.railbow.yml`, `.railbow.local.yml`, and `RBW_*` environment variables;
  interactive `railbow init` / `rake railbow:init` generator.
- `railbow` CLI wrapper to use Railbow without touching a project's Gemfile,
  plus `railbow demo` showcase.
- Smart auto-disable in CI, piped output, `NO_COLOR`, and LLM agents.
