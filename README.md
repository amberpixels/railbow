<p align="center">
  <img src="logo.svg" alt="Railbow" width="580">
</p>

<div align="center">

[![Gem Version](https://img.shields.io/gem/v/railbow)](https://rubygems.org/gems/railbow)
[![CI](https://github.com/amberpixels/railbow/actions/workflows/ci.yml/badge.svg)](https://github.com/amberpixels/railbow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE.txt)

</div>

**Make your Rails CLI output beautiful.** Railbow enhances migrations, routes, stats, notes, and more with colorful, emoji-rich, information-dense formatting.

## Features

- **Migrations** - colorful `db:migrate` output with readable millisecond timing
- **Migration Status** - rich `db:migrate:status` with git authors, calendar view, table detection, landing dates, and time filtering
- **Routes** - color-coded HTTP verbs and highlighted parameters in `rails routes`
- **Stats** - beautiful `rails stats` tables
- **Notes** - `rails notes` with git blame, author colors, date filtering, and sorting
- **About** - polished `rails about` output
- **Git Integration** - authors, diffs, branch origin, landing dates, uncommitted file indicators
- **Calendar View** - month separators plus week ticks or full week rows, with optional per-section counts
- **Multiple Databases** - read one table by default, the rest summarized in a line each (and expanded when they have migrations pending); sharded databases merged with a status per shard
- **Ghost Recovery** - uses the [mighost](https://github.com/amberpixels/mighost) gem (optional) to recover names, authors, and branch badges for `NO FILE` migrations
- **Smart Defaults** - auto-disables in CI, piped output, `NO_COLOR`, and LLM agents

## Installation

### Option A: Add to your Gemfile (recommended)

```ruby
gem "railbow", group: :development
```

```bash
bundle install
```

### Option B: Use the CLI wrapper (no Gemfile changes)

```bash
gem install railbow
railbow rake db:migrate:status
railbow rails routes
```

The CLI creates a temporary wrapper so Railbow loads automatically without modifying your project's Gemfile.

## Usage

Railbow works automatically once installed. Every example below works with both `rails` and `rake` commands.

### `rails db:migrate`

**Before:**
```
==  CreateProducts: migrating =================================================
-- create_table(:products)
   -> 0.0028s
==  CreateProducts: migrated (0.0028s) ========================================
```

**After:**
```
🚀 CreateProducts: migrating...
  ✓ create_table(:products) → 2.8ms
✅ CreateProducts: migrated (2.8ms total)
```

### `rails db:migrate:status`

This is Railbow's flagship feature. The plain Rails output:

```
Status   Migration ID    Migration Name
--------------------------------------------------
up       20260202145343  Add weight field to animals
up       20260203134528  Create vaccination records
up       20260210183902  Create pet tags
up       20260303120000  Add breed restrictions to adoption policies
up       20260313132325  Create veterinary appointments
```

becomes a rich, information-dense dashboard (with default config):

```
         Feb 2026   W06
 ↑↑    │ 20260202145343 │ 2026-02-02 14:53:43 │ Add weight field to animals          ● animals
 ↑↑    │ 20260203134528 │ 2026-02-03 13:45:28 │ Create vaccination records           ● vaccination_records
 ↑↑    │ 20260210183902 │ 2026-02-10 18:39:02 │ Create pet tags              ⤻ Mar 04  ● pet_tags
───────┼────────────────┼─────────────────────┼──────────────────────────────
         Mar 2026   W10
 ↑↑    │ 20260303120000 │ 2026-03-03 12:00:00 │ Add breed restrictions to…   ⤻ Mar 13  ● adoption_policies
 ↑↑    │ 20260313132325 │ 2026-03-13 13:23:25 │ Create veterinary appointm…  ⎇ PS-142  ● veterinary_appointments
```

Out of the box you get:

- **Calendar separators** - month + ISO week headers to orient you in time
- **Status aliases** - `↑↑` / `↓↓` instead of `up` / `down` (customizable)
- **Created At** - timestamp parsed from the migration ID
- **Landing dates** - `⤻ Mar 04` badge when a migration was merged to main after its creation
- **Branch badges** - `⎇ PS-142` showing the source branch/ticket
- **Affected tables** - color-coded table names extracted from migration files
- **Time filtering** - only the last 70 days shown by default (`since: 70d`), as a soft limit: never fewer than 10 migrations, however old (`since_min: 10`)
- **Your migrations highlighted** - rows authored by you are visually distinct
- **Pending migrations greyed out** - a `down` row keeps its status glyph but loses its colors

#### Weekly view

By default each new ISO week is marked with a tick on the date column
(`calendar: wticks`). For a fuller weekly breakdown, `wdividers` gives every
week its own separator row, and `counts` appends how many migrations sit under
each separator, week or month:

```bash
RBW_CALENDAR=wdividers,counts rake db:migrate:status
```

```
         Feb 2026   W06 · 2 migrations
 ↑↑    │ 20260202145343 │ 2026-02-02 14:53:43 │ Add weight field to animals          ● animals
 ↑↑    │ 20260203134528 │ 2026-02-03 13:45:28 │ Create vaccination records           ● vaccination_records
         Feb 2026   W07 · 1 migration
 ↑↑    │ 20260210183902 │ 2026-02-10 18:39:02 │ Create pet tags                      ● pet_tags
         Mar 2026   W10 · 1 migration
 ↑↑    │ 20260303120000 │ 2026-03-03 12:00:00 │ Add breed restrictions to…           ● adoption_policies
         Mar 2026   W11 · 1 migration
 ↑↑    │ 20260313132325 │ 2026-03-13 13:23:25 │ Create veterinary appointm…  ⎇ PS-142  ● veterinary_appointments
```

Every separator carries the month, so the week number always sits at the same
offset instead of shifting left on rows that open no new month, and every
separator is drawn in the same muted purple. Both labels are `strftime`
patterns: `label:` for months, `wlabel:` for weeks (defaulting to the same
pattern).

`RBW_CALENDAR` is the list of *week* markers, so an empty value leaves you with
month separators and nothing else:

```yaml
view: "calendar,tables"
calendar: ""            # month separators only
```

Dropping `calendar` from `view` instead removes the month separators too.

#### Multiple databases

Rails runs `db:migrate:status` once per database, so a multi-database app used
to get one blind table per database: widths that did not line up, the help
printed once per database, and every git lookup repeated. Railbow now renders
the whole run together.

By default you read one table: the first database in `database.yml` is rendered
in full and every other one is summarized in a line each (`db: focus`).

```
📊 2 databases · primary, log

──── primary · myapp_development ──── 12 of 240 ────────────────────────
 ↑↑  │ 20260721130000 │ 2026-07-21 13:00:00 │ Partition visit reminders    ● visit_reminders
 ↓↓  │ 20260727170000 │ 2026-07-27 17:00:00 │ Add microchip ids to animals ● animals

⋯ log · 5 migrations, all applied · latest Jul 22 2026
```

**A database with migrations pending is always expanded**, however focused the
run is. The summary exists to hide what needs no action, and pending work is
the opposite of that.

Setting `db` to an empty value expands every database that has recent activity,
each as its own section with column widths shared so the tables line up:

```yaml
db: ""            # or RBW_DB= on the command line
```

```
──── primary · myapp_development ──── 12 of 240 ────────────────────────
 ↑↑  │ 20260721130000 │ 2026-07-21 13:00:00 │ Partition visit reminders    ● visit_reminders

──── log · log_development ─────────────────────────────────────────────
 ↑↑  │ 20260722120000 │ 2026-07-22 12:00:00 │ Drop archived visit logs     ● archived_visit_logs
```

A section header counts what it is showing: `12 of 240` means 12 fell inside
the time window. When the window found too few and the `since_min` floor topped
the section back up, it reads `last 10 of 50` instead, because the rows are
then the newest ten rather than a window's worth.

Even then, a database with nothing in the time window collapses to one line
rather than an empty table, which is what keeps the `cache`, `queue` and
`cable` databases of a stock Rails 8 app from drowning out your own:

```
⋯ cache · 5 migrations, all applied · latest Feb 12 2024
⋯ queue · 12 migrations, 3 pending outside the 70d window - RBW_SINCE=all
```

Databases that share a `migrations_paths` (horizontal sharding) run the same
files, so they merge into one table carrying a status per database. Drift
between shards is then visible at a glance, and `·` marks a version a shard has
never seen:

```
──── primary + primary_shard_one · db/migrate ──────────────────────────
 ↑↑ ↑↑ │ 20260601151200 │ 2026-06-01 15:12:00 │ Add owner id to pets
 ↑↑ ↓↓ │ 20260726143000 │ 2026-07-26 14:30:00 │ Add policy number to bills
```

`RBW_DB` controls the rest: `only:<name>` and `skip:<name>` (both repeatable)
pick databases, `full` draws every section in full and overrides `focus`, and
`inline` merges everything into a single table ordered by version with a `Db`
column, so the calendar spans the whole application rather than restarting per
database. `focus` never applies to an inline run - a merged table exists to
hold every database at once.

A single-database app sees none of this: its output is unchanged.

If the [mighost](https://github.com/amberpixels/mighost) gem is installed (`gem "mighost", group: [:development, :test]`), migrations whose files were deleted (e.g. after switching branches) show up with a 👻 status and their recovered name instead of a bare `********** NO FILE **********` row - Railbow talks to it through the stable `Mighost::API`. Each ghost row carries the most informative badge mighost can provide: `≡ <version>` when the migration was re-timestamped and lives on under another version (shown with a calmer 🪦 status), `⌥ <branch>` when a branch still holds the file, or `✂ deleted in:<sha>` pointing at the commit that removed it. Ghosts dismissed via `mighost:dismiss` (or hidden by `hide_superseded`) render as plain `NO FILE`.

### `rails db:migrate:down`

```
⏪ CreateProducts: reverting...
  ✓ drop_table(:products) → 1.2ms
✅ CreateProducts: reverted (1.2ms total)
```

### `rails routes`

HTTP verbs are color-coded (GET=green, POST=yellow, PATCH/PUT=cyan, DELETE=red), route parameters (`:id`, `*splat`) are highlighted, and controller#action pairs stand out.

### `rails stats`

Code statistics rendered as a colorful table with highlighted totals and code-to-test ratio.

### `rails notes`

Annotations enriched with git blame data - author names, commit dates, and color-coded tags (TODO=yellow, FIXME=red, OPTIMIZE=cyan, HACK=red, NOTE=green).

## Configuration

Railbow works with zero configuration, but everything is customizable.

### Config files

Config is loaded in layers (each overrides the previous):

1. **Built-in defaults**
2. **Global:** `~/.config/railbow/config.yml`
3. **Project:** `.railbow.yml` (commit to git)
4. **Local:** `.railbow.local.yml` (gitignored, personal overrides)

Generate a config interactively:

```bash
railbow init
# or, within a Rails project:
rake railbow:init
```

### Example `.railbow.yml`

```yaml
since: 70d
since_min: 10
date: rel
git: "author:me,diff,mask:auto"
view: "calendar,tables"
calendar: wticks
db: focus

compact: "maxw:120"

aliases:
  columns:
    Status: Live
  values:
    Status:
      up: "↑↑"
      down: "↓↓"
```

### Environment variables

Every option can also be set via `RBW_*` environment variables, which override config files:

| Variable | Example | Description |
|---|---|---|
| `RBW_PLAIN` | `1` | Disable all formatting |
| `RBW_FORCE` | `1` | Force formatting even when piped, in CI, or run by an LLM agent (`RBW_PLAIN=1` still wins) |
| `RBW_SINCE` | `2mo`, `70d`, `1y`, `all` | Filter migrations by time period |
| `RBW_SINCE_MIN` | `10`, `0` | Never show fewer than this many migrations, however old (default 10; `0` disables) |
| `RBW_DATE` | `full`, `rel`, `short`, `custom(%b %d)` | Date display format |
| `RBW_GIT` | `author:me,diff,mask:auto` | Git integration options |
| `RBW_VIEW` | `calendar,tables` | Enable calendar view and table detection |
| `RBW_CALENDAR` | `wticks`, `wdividers,counts`, `` (empty) | Week markers: tick marks, full week separator rows, per-section counts. Empty means month separators only |
| `RBW_DB` | `focus` (default), `` (empty), `only:primary`, `skip:cache`, `full`, `inline` | Multi-database runs: focus one database, expand them all, pick some, or merge them into one table |
| `RBW_COMPACT` | `oneline,dense,noheader,maxw:80` | Compact display options |
| `RBW_VERB` | `GET,POST` | Filter routes by HTTP method |
| `RBW_SORT` | `file`, `date` | Sort order for notes |
| `RBW_HELP` | `1` | Show help messages |

### Quick examples

```bash
# Last 2 months, calendar view
RBW_SINCE=2mo rake db:migrate:status

# Relative dates, highlight your migrations
RBW_DATE=rel RBW_GIT=author:me rake db:migrate:status

# Full git context with table detection
RBW_GIT=author:all,diff RBW_VIEW=tables rake db:migrate:status

# Only GET routes
RBW_VERB=GET rails routes

# Notes sorted by commit date
RBW_SORT=date rails notes
```

## How It Works

Railbow integrates through a Rails Railtie - it prepends formatter modules onto existing Rails classes without modifying your code:

- `ActiveRecord::Migration` - migration output
- `ActiveRecord::Tasks::DatabaseTasks` - migration status
- `ActionDispatch::Routing::ConsoleFormatter::Sheet` - routes
- `Rails::Info` - about
- `Rails::SourceAnnotationExtractor` - notes

Formatting auto-disables when:
- `RBW_PLAIN=1` or `NO_COLOR` is set
- Running in CI (`CI` env var)
- Output is piped or redirected (non-TTY)
- Running inside an LLM agent (`CLAUDECODE` env var)

`RBW_FORCE=1` overrides all of the auto-detection above (useful for capturing
formatted output to a file, or letting an agent inspect the real rendering).
An explicit `RBW_PLAIN=1` always wins over `RBW_FORCE`.

## Requirements

- Ruby >= 3.1.0
- Rails >= 7.2 (including 8.x)

## Development

```bash
bin/setup          # Install dependencies
bundle exec rake   # Run tests + linting (RSpec + Standard)
bin/console        # Interactive prompt
```

## Contributing

Bug reports and pull requests are welcome at [github.com/amberpixels/railbow](https://github.com/amberpixels/railbow).

## License

MIT License. See [LICENSE.txt](https://github.com/amberpixels/railbow/blob/main/LICENSE.txt).
