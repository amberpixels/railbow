# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
