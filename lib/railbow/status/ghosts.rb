# frozen_string_literal: true

module Railbow
  module Status
    # Recovery of "NO FILE" migrations through the optional mighost gem: rows
    # applied to the database whose migration file is no longer on disk.
    module Ghosts
      GHOST_FG = "\e[38;5;217m" # matches Table::Renderer::GHOST_FG, the row it sits in
      MUTED = "\e[38;5;245m"
      BRANCH = "\e[38;5;222m"

      # A ghost normalized for rendering, whether it came from mighost's orphan
      # classification or from a live snapshot recovery.
      class Row
        attr_reader :filename, :branch_name, :source, :superseded_by, :deleted_in_sha,
          :author_name, :author_email, :content

        def initialize(filename: nil, branch_name: nil, source: nil, superseded_by: nil,
          deleted_in_sha: nil, author_name: nil, author_email: nil, content: nil)
          @filename = filename
          @branch_name = branch_name
          @source = source
          @superseded_by = superseded_by
          @deleted_in_sha = deleted_in_sha
          @author_name = author_name
          @author_email = author_email
          @content = content
        end
      end

      module_function

      def available?
        defined?(Mighost::API) && Mighost.enabled?
      end

      def load(versions, with_content: false)
        # Detect once: OrphanedMigration carries the classification (supersession,
        # deletion commit) that a bare snapshot does not, and already honors
        # dismissals and hide_superseded.
        orphans = begin
          Mighost::API.orphaned_migrations.to_h { |o| [o.version.to_s, o] }
        rescue
          return {}
        end

        rows = {}
        versions.each do |v|
          # Absent from detect = deliberately suppressed (dismissed, or superseded
          # with hide_superseded on) - render as plain NO FILE, do not re-recover.
          next unless (orphan = orphans[v])

          row = if orphan.filename && !orphan.filename.empty?
            from_orphan(orphan, v, with_content)
          else
            from_live_recovery(v, with_content)
          end
          rows[v] = row if row
        end
        rows
      end

      def from_orphan(orphan, version, with_content)
        Row.new(
          filename: orphan.filename,
          branch_name: orphan.branch_name,
          source: read_attr(orphan, :source),
          superseded_by: read_attr(orphan, :superseded_by),
          deleted_in_sha: read_attr(orphan, :deleted_in_sha),
          author_name: read_attr(orphan, :author_name),
          author_email: read_attr(orphan, :author_email),
          content: with_content ? snapshot_content(version) : nil
        )
      end

      # Detect reads stored snapshots only. A version it lists without a filename
      # has no snapshot yet, so fall back to live git/worktree recovery - that
      # keeps fresh clones working with zero setup.
      def from_live_recovery(version, with_content)
        snapshot = begin
          Mighost::API.find_or_recover_snapshot(version)
        rescue
          nil
        end
        return nil unless snapshot&.filename && !snapshot.filename.empty?

        Row.new(
          filename: snapshot.filename,
          branch_name: snapshot.branch_name,
          source: read_attr(snapshot, :source),
          superseded_by: api_superseded_by(version),
          deleted_in_sha: read_attr(snapshot, :deleted_in_sha),
          author_name: read_attr(snapshot, :author_name),
          author_email: read_attr(snapshot, :author_email),
          content: with_content ? snapshot.content : nil
        )
      end

      def read_attr(obj, name)
        obj.respond_to?(name) ? obj.public_send(name) : nil
      end

      def snapshot_content(version)
        Mighost::API.find_snapshot(version)&.content
      rescue
        nil
      end

      def api_superseded_by(version)
        return nil unless Mighost::API.respond_to?(:superseded_by)

        Mighost::API.superseded_by(version)
      rescue
        nil
      end

      # One tag slot per ghost row; the most informative wins. Each ends in the
      # ghost foreground rather than a reset, so the rest of the row keeps its
      # ghost styling.
      def tag(ghost)
        if ghost.superseded_by
          "#{MUTED}≡ #{ghost.superseded_by}#{GHOST_FG}"
        elsif ghost.branch_name
          if ghost.source == "worktree"
            "#{BRANCH}⌥ₜ#{ghost.branch_name}#{GHOST_FG}"
          else
            "#{BRANCH}⌥ #{ghost.branch_name}#{GHOST_FG}"
          end
        elsif ghost.deleted_in_sha
          "#{MUTED}✂ deleted in:#{ghost.deleted_in_sha[0, 8]}#{GHOST_FG}"
        end
      end

      # The name a ghost row displays, derived from its recovered filename.
      def display_name(ghost)
        ghost.filename
          .sub(/\A\d+_/, "")      # strip version prefix
          .sub(/\.rb\z/, "")      # strip extension
          .tr("_", " ")
          .gsub(/\b\w/, &:upcase) # titleize
      end
    end
  end
end
