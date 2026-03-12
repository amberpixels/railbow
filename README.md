# Railbow

```
 ░█▀▀█ ░█▀▀█ ▀█▀ ░█─── ░█▀▀█ ░█▀▀▀█ ░█───░█
 ░█▄▄▀ ░█▄▄█ ░█─ ░█─── ░█▀▀▄ ░█──░█ ░█─█─░█
 ░█─░█ ░█─░█ ▄█▄ ░█▄▄█ ░█▄▄█ ░█▄▄▄█ ─░█░█─
```

**Make your Rails CLI output beautiful.** Railbow enhances migrations, routes, stats, notes, and more with colorful, emoji-rich, information-dense formatting.

## Features

- **Migrations** - colorful `db:migrate` output with readable millisecond timing
- **Migration Status** - rich `db:migrate:status` with git authors, calendar view, table detection, landing dates, and time filtering
- **Routes** - color-coded HTTP verbs and highlighted parameters in `rails routes`
- **Stats** - beautiful `rails stats` tables
- **Notes** - `rails notes` with git blame, author colors, date filtering, and sorting
- **About** - polished `rails about` output
- **Git Integration** - authors, diffs, branch origin, landing dates, uncommitted file indicators
- **Calendar View** - month separators and week tick markers for migration timelines
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

**Before:**
```
database: db/development.sqlite3

Status   Migration ID    Migration Name
--------------------------------------------------
up       20140711185212  Create documentation pages
down     20160213170731  Create owners
```

**After:**
```
📊 Database: db/development.sqlite3

 Status  Migration ID    Created At           Migration Name
 up     │ 20140711185212 │ 2014-07-11 18:52:12 │ Create documentation pages
 down   │ 20160213170731 │ 2016-02-13 17:07:31 │ Create owners
```

With git integration enabled (default), you also get author names, landing dates, branch origin badges, affected table names, and calendar month separators.

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

Annotations enriched with git blame data — author names, commit dates, and color-coded tags (TODO=yellow, FIXME=red, OPTIMIZE=cyan, HACK=red, NOTE=green).

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
date: rel
git: "author:me,diff,mask:auto"
view: "calendar,tables"
calendar: wticks

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
| `RBW_SINCE` | `2mo`, `70d`, `1y`, `all` | Filter migrations by time period |
| `RBW_DATE` | `full`, `rel`, `short`, `custom(%b %d)` | Date display format |
| `RBW_GIT` | `author:me,diff,mask:auto` | Git integration options |
| `RBW_VIEW` | `calendar,tables` | Enable calendar view and table detection |
| `RBW_CALENDAR` | `wticks` | Show week tick markers |
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

Railbow integrates through a Rails Railtie — it prepends formatter modules onto existing Rails classes without modifying your code:

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
