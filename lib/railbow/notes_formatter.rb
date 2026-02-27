# frozen_string_literal: true

require "zlib"
require "open3"
require "date"
require_relative "formatters/base"
require_relative "logo"
require_relative "color_assigner"

module Railbow
  module NotesFormatter
    RESET = Formatters::Base::RESET
    BOLD = Formatters::Base::BOLD
    DIM = Formatters::Base::DIM
    RED = Formatters::Base::RED
    YELLOW = Formatters::Base::YELLOW
    CYAN = Formatters::Base::CYAN
    GREEN = Formatters::Base::GREEN
    WHITE = Formatters::Base::BRIGHT_WHITE

    BAR = "\u258e" # ▎

    TAG_COLORS = {
      "TODO" => YELLOW,
      "FIXME" => RED,
      "OPTIMIZE" => CYAN,
      "HACK" => RED,
      "NOTE" => GREEN
    }.freeze

    PALETTE = Formatters::Base::TABLE_PALETTE

    def display(results, options = {})
      return super if Railbow.plain?

      if Railbow::Params.help?
        print_help
        return
      end

      author_mode = Railbow::Params.git_author
      since_val = Railbow::Params.since
      sort_mode = Railbow::Params.sort

      since_date = Railbow::Params.parse_since(since_val, context: "annotations")
      git_needed = %w[all me].include?(author_mode) || since_date || sort_mode == "date"

      # Build blame cache for all files if git features are needed
      blame_cache = {}
      if git_needed
        results.each_key do |source_file|
          blame_cache[source_file] ||= blame_file(source_file)
        end
      end

      # Flatten annotations into a list for filtering/sorting
      entries = []
      results.each do |source_file, annotations|
        annotations.each do |annotation|
          blame_info = blame_cache.dig(source_file, annotation.line)
          entries << {
            file: source_file,
            annotation: annotation,
            blame: blame_info
          }
        end
      end

      # Filter by SINCE
      skipped = 0
      if since_date
        before = entries.size
        entries = entries.select do |entry|
          entry[:blame] && entry[:blame][:date] && entry[:blame][:date] >= since_date
        end
        skipped = before - entries.size
      end

      # Sort by date (newest first) when requested
      if sort_mode == "date"
        entries.sort_by! do |entry|
          d = entry.dig(:blame, :date)
          d ? -d.to_time.to_i : 0
        end
      end

      # Determine "me" identity
      git_email = nil
      if author_mode == "me"
        git_email = current_git_email
      end

      # Determine max location width for alignment when showing metadata
      show_date = git_needed
      max_loc_width = 0
      author_colors = nil
      if author_mode == "all"
        author_names = entries.filter_map { |e| e.dig(:blame, :author) }.uniq
        author_colors = ColorAssigner.new(author_names)
      end
      if show_date || author_mode == "all"
        entries.each do |entry|
          loc = "#{entry[:file]}:#{entry[:annotation].line}"
          max_loc_width = loc.length if loc.length > max_loc_width
        end
      end

      # Group entries back by file for bar coloring
      file_counts = Hash.new(0)
      entries.each { |e| file_counts[e[:file]] += 1 }

      # Display
      entries.each do |entry|
        source_file = entry[:file]
        annotation = entry[:annotation]
        blame_info = entry[:blame]

        is_mine = author_mode == "me" && git_email && blame_info &&
          blame_info[:email] == git_email

        bar_color = if file_counts[source_file] > 1
          color_code = PALETTE[Zlib.crc32(source_file.to_s) % PALETTE.size]
          "\e[38;5;#{color_code}m"
        else
          DIM
        end
        colored_bar = "#{bar_color}#{BAR}#{RESET}"
        # When highlighting "me", use bright white bar
        colored_bar = "#{WHITE}#{BAR}#{RESET}" if is_mine

        tag = annotation.tag
        tag_color = TAG_COLORS[tag] || DIM
        location = "#{source_file}:#{annotation.line}"
        colored_tag = "#{tag_color}#{BOLD}#{tag}#{RESET}"
        note = annotation.text.to_s.encode("UTF-8", invalid: :replace, undef: :replace)

        # Build the file:line row with optional author+date
        loc_line = " #{colored_bar} #{location}"

        if author_mode == "all" && blame_info
          author_name = blame_info[:author] || ""
          blame_date = blame_info[:date] ? blame_info[:date].strftime("%Y-%m-%d") : ""
          padding = " " * [(max_loc_width - location.length + 2), 2].max
          colored_author = "#{author_colors.color_for(author_name)}#{author_name}#{RESET}"
          meta = "#{colored_author}  #{DIM}#{blame_date}#{RESET}"
          loc_line = " #{colored_bar} #{location}#{padding}#{meta}"
        elsif author_mode == "me" && is_mine && blame_info
          blame_date = blame_info[:date] ? blame_info[:date].strftime("%Y-%m-%d") : ""
          loc_line = " #{colored_bar} #{WHITE}#{location}#{RESET}  #{DIM}#{blame_date}#{RESET}"
        elsif author_mode != "all" && show_date && blame_info
          blame_date = blame_info[:date] ? blame_info[:date].strftime("%Y-%m-%d") : ""
          padding = " " * [(max_loc_width - location.length + 2), 2].max
          loc_line = " #{colored_bar} #{location}#{padding}#{DIM}#{blame_date}#{RESET}"
        end

        puts loc_line

        # Wrap note text so continuation lines keep the bar and align after TAG
        prefix = " #{colored_bar}   "
        tag_str = "#{colored_tag} "
        indent_width = 1 + 1 + 1 + 3 + tag.length + 1 # " " + BAR + " " + "   " + TAG + " "
        continuation_prefix = " #{colored_bar}   #{" " * (tag.length + 1)}"

        # Apply "me" highlighting to note text
        if is_mine
          tag_str = "#{WHITE}#{tag}#{RESET} "
        end

        term_w = ($stdout.tty? && $stdout.respond_to?(:winsize)) ? $stdout.winsize[1] : 120
        max_note_width = [term_w - indent_width, 20].max

        if note.length <= max_note_width
          note_text = is_mine ? "#{WHITE}#{note}#{RESET}" : note
          puts "#{prefix}#{tag_str}#{note_text}"
        else
          lines = word_wrap_simple(note, max_note_width)
          first_line = is_mine ? "#{WHITE}#{lines.first}#{RESET}" : lines.first
          puts "#{prefix}#{tag_str}#{first_line}"
          lines[1..].each do |line|
            line_text = is_mine ? "#{WHITE}#{line}#{RESET}" : line
            puts "#{continuation_prefix}#{line_text}"
          end
        end
      end

      if skipped > 0
        puts
        puts "  #{DIM}#{skipped} annotation(s) older than #{since_val} hidden#{RESET}"
      end

      puts
    end

    private

    def blame_file(path)
      return {} unless File.exist?(path)

      output, status = Open3.capture2("git", "blame", "--porcelain", path)
      return {} unless status.success?

      result = {}
      current_line = nil
      current_author = nil
      current_email = nil
      current_time = nil

      output.each_line do |line|
        line = line.chomp
        if line.match?(/\A[0-9a-f]{40}\s/)
          parts = line.split
          current_line = parts[2]&.to_i
          current_author = nil
          current_email = nil
          current_time = nil
        elsif line.start_with?("author ")
          current_author = line.sub("author ", "")
        elsif line.start_with?("author-mail ")
          current_email = line.sub("author-mail ", "").delete("<>").strip.downcase
        elsif line.start_with?("author-time ")
          current_time = line.sub("author-time ", "").to_i
        elsif line.start_with?("\t") && current_line
          # End of this blame entry — store it
          date = current_time ? Time.at(current_time).to_date : nil
          result[current_line] = {
            author: current_author,
            email: current_email,
            date: date
          }
        end
      end

      result
    end

    def current_git_email
      output, _status = Open3.capture2("git", "config", "user.email")
      output.strip.downcase
    end

    def print_help
      Railbow.print_logo
      puts <<~HELP

        Enhanced rails notes

        \e[1mUsage:\e[0m
          [RBW_*=value ...] rails notes

        \e[1mOptions:\e[0m
          RBW_GIT=<options>        Git integration (comma-separated):
                                   author     — show all authors (same as author:all)
                                   author:all — show author + date on each annotation
                                   author:me  — highlight your own annotations

          RBW_SINCE=<period>       Filter annotations by blame date (default: all)
                                   Values: all, 2mo, 1w, 30d, 1y, etc.
                                   Units: d (days), w (weeks), mo/m (months), y (years)

          RBW_SORT=<mode>          Sort order (default: file)
                                   file — group by file (default Rails order)
                                   date — sort by blame date (newest first)

          RBW_PLAIN=1              Disable Railbow formatting (plain Rails output)

          RBW_HELP=1               Show this help message

        \e[2mAuto-disabled when piped, in CI, or when called by an LLM agent.\e[0m

        \e[1mExamples:\e[0m
          rails notes
          RBW_GIT=author rails notes
          RBW_GIT=author:me rails notes
          RBW_SINCE=1mo RBW_GIT=author rails notes
          RBW_SORT=date RBW_GIT=author rails notes
          RBW_SINCE=2w RBW_GIT=author:me RBW_SORT=date rails notes

      HELP
    end

    def word_wrap_simple(text, max_width)
      lines = []
      current = +""
      current_width = 0

      text.split(/(\s+)/).each do |token|
        if current_width + token.length <= max_width
          current << token
          current_width += token.length
        elsif current_width.zero?
          lines << token
        else
          lines << current.rstrip
          token = token.lstrip
          current = +token
          current_width = token.length
        end
      end

      lines << current.rstrip unless current.strip.empty?
      lines
    end
  end
end
