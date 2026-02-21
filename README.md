# Shine ✨

Make your Rails database migrations beautiful! Shine enhances Rails migration command output with modern, colorful, emoji-enhanced formatting.

## Features

- 🎨 **Colorful Output**: Color-coded migration status and timing information
- ⚡ **Readable Timing**: Millisecond-precision timing display
- 🎯 **Enhanced Status Display**: Beautiful table format for `db:migrate:status`
- 🚀 **Zero Configuration**: Works immediately after installation
- ✅ **Rails 7.2+ Compatible**: Supports Rails 7.2+ and 8.x

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'shine'
```

Then execute:

```bash
bundle install
```

That's it! No configuration needed. Your migrations will now look beautiful.

## Usage

Shine automatically enhances these Rails commands:

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

### `rails db:migrate:down VERSION=xxx`

**Before:**
```
==  CreateProducts: reverting ================================================
-- drop_table(:products)
   -> 0.0012s
==  CreateProducts: reverted (0.0012s) =======================================
```

**After:**
```
⏪ CreateProducts: reverting...
  ✓ drop_table(:products) → 1.2ms
✅ CreateProducts: reverted (1.2ms total)
```

## How It Works

Shine integrates seamlessly with Rails through a Railtie. It:

1. Prepends formatting methods to `ActiveRecord::Migration`
2. Overrides the `db:migrate:status` Rake task
3. Adds colorization, emojis, and timing enhancements
4. Maintains full compatibility with standard Rails behavior

No changes to your migrations or existing code are required.

## Requirements

- Ruby >= 3.1.0
- Rails >= 7.2
- ActiveRecord >= 7.2

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amberpixels/shine. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/amberpixels/shine/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Shine project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/amberpixels/shine/blob/main/CODE_OF_CONDUCT.md).
