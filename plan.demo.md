# Plan: `railbow demo` command

## Goal

Allow anyone to experience railbow with zero setup:

```bash
gem install railbow
railbow demo
```

No Rails project. No database. No cloning anything. Just the gem and a terminal.

---

## What `railbow demo` should do

Run `rails db:migrate:status` output through the real railbow formatter using
pre-baked fake migration data. The output must look like a real mid-sized Rails
project — curated to showcase every major feature at once.

Optionally support:
```bash
railbow demo routes     # shows formatted rails routes output
railbow demo migrate    # shows rails db:migrate output  
railbow demo status     # default: db:migrate:status (most impressive)
railbow demo all        # cycles through all formatters
```

---

## Architecture

### New files to create

```
lib/railbow/demo/
  runner.rb          # entry point, dispatches to sub-demos
  status_demo.rb     # fake db:migrate:status data + runner
  migrate_demo.rb    # fake db:migrate sequence
  routes_demo.rb     # fake rails routes output
  fixtures.rb        # shared fake data (projects, authors, tables, branches)
```

### Integration point

In `exe/railbow` (the CLI entrypoint), add handling for the `demo` subcommand
before the existing Rails command passthrough:

```ruby
if ARGV[0] == "demo"
  require "railbow/demo/runner"
  Railbow::Demo::Runner.run(ARGV[1] || "status")
  exit 0
end
```

---

## Fake data design (`fixtures.rb`)

Design the fake data to maximally showcase railbow's features. Use a fictional
pet shop SaaS project — concrete enough to feel real.

### Migrations fixture (~20 migrations)

Span 3 months. Include:
- **Month separators** — at least 3 calendar blocks (Jan, Feb, Mar 2026)
- **Mix of up/down** — ~17 up, 3 down at the end (pending)
- **Landing date badges** (`⤻`) — ~5 migrations where landing_date > created_at
- **Branch badges** (`⎇ VET-xxx`) — ~8 migrations with branch/ticket refs
- **Various affected tables** — pets, owners, appointments, vaccinations,
  billing_records, veterinarians, etc. (drives table color variety)
- **Multiple authors** — 3 fake authors + "me" (current user) for author
  highlighting. The "me" detection should use a sentinel that demo mode
  overrides, OR just hardcode one author as highlighted.
- **Mix of migration types** — create_table, add_column, add_index, rename_column

Example fixture shape (adapt to your actual internal model):

```ruby
MIGRATIONS = [
  {
    status: "up",
    version: "20260101093012",
    name: "CreatePets",
    author: "alice",
    branch: nil,
    landing_date: nil,
    tables: ["pets"],
  },
  {
    status: "up",
    version: "20260108141500",
    name: "CreateOwners",
    author: "bob",
    branch: "VET-12",
    landing_date: Date.new(2026, 1, 10),
    tables: ["owners"],
  },
  # ... ~18 more
  {
    status: "down",
    version: "20260315110000",
    name: "AddInsuranceFieldsToBilling",
    author: "eugene",   # "me" — highlighted
    branch: "VET-198",
    landing_date: nil,
    tables: ["billing_records"],
  },
]
```

### Routes fixture (~15 routes)

Cover all HTTP verbs (GET, POST, PUT, PATCH, DELETE) across several resources.
Include nested routes with `:id` params and a couple of wildcard/namespaced ones.

### Migrate fixture (~5 migrations running)

Simulate a `db:migrate` sequence with timing: migrating → migrated steps,
including one slower migration (~230ms) to show timing variety.

---

## `status_demo.rb` implementation sketch

```ruby
module Railbow
  module Demo
    class StatusDemo
      def self.run
        # 1. Load fixtures
        migrations = Fixtures::MIGRATIONS

        # 2. Instantiate the same formatter used in production
        #    (exact class name depends on your internal API)
        formatter = Railbow::Formatters::MigrationStatus.new(
          config: demo_config,
          current_user: "eugene"   # hardcoded for demo; drives "me" highlighting
        )

        # 3. Feed fake data directly, bypass Rails entirely
        formatter.render(migrations)
      end

      def self.demo_config
        # Full-featured config: calendar on, git on, tables on, relative dates
        Railbow::Config.new(
          since: "all",          # show everything, not last 70d
          git: "author:me,diff",
          view: "calendar,tables",
          calendar: "wticks",
          date: "rel",
        )
      end
    end
  end
end
```

**Key constraint:** `StatusDemo` must NOT require ActiveRecord, Rails, or a DB
connection. If the existing formatter currently has Rails dependencies, extract
the pure rendering logic first, then call it from both the real railtie hook and
the demo runner.

---

## Output quality checklist

Before shipping, run `railbow demo` and verify:

- [ ] At least 3 month/week separator blocks visible
- [ ] At least one `⤻ Mar 13` landing date badge visible
- [ ] At least one `⎇ VET-xxx` branch badge visible
- [ ] "me" author rows visually distinct from others
- [ ] At least 4 different table colors visible
- [ ] Mix of `↑↑` and `↓↓` status indicators
- [ ] Calendar week ticks present
- [ ] Output fills ~30 terminal lines (enough to be impressive, not overwhelming)
- [ ] Runs in < 1 second (it's all in-memory, should be instant)
- [ ] No errors when run outside a Rails project directory
- [ ] No errors when Rails gem is not installed at all

---

## README update (after implementation)

Replace current installation section opener with:

```markdown
## Try it in 10 seconds

```bash
gem install railbow
railbow demo
```

No Rails project needed. See what your migrations could look like.
```

Then existing installation/usage sections follow below.

---

## Stretch: animated GIF from `railbow demo`

Once implemented, record `railbow demo` output with `vhs` or `asciinema` for
the README hero. The demo fixture data is specifically designed to look good in
a recording — this is intentional. The GIF becomes the primary marketing asset.

---

## Out of scope for this plan

- `railbow demo PROJ=xxx` (clone + setup a real project) — too fragile
- Interactive/paginated demo output
- Demo data that changes on each run (keep it deterministic)
