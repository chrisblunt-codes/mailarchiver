# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "db"
require "sqlite3"

module MailArchiver
  module DBA
    @@db : DB::Database?

    def self.db : DB::Database
      @@db ||= DB.open(ENV["ARCHIVE_DB"]? || "sqlite3:./data/mailarchiver.db")
    end

    def self.migrate!
      sql = File.read("./db/migrate.sql")
      stmts = split_sql_script(sql)

      db.transaction do |tx|
        tx.connection.exec "PRAGMA foreign_keys = ON;"

        stmts.each do |raw|
          # skip if this chunk has only comments/whitespace
          non_comment = raw.split(/\n/).reject { |ln| ln.lstrip.starts_with?("--") }.join("\n")
          next if non_comment.strip.empty?

          tx.connection.exec raw
        rescue e
          STDERR.puts "\n--- Migration statement failed ---\n#{raw}\n----------------------------------"
          raise e
        end
      end
    end

    # Keep CREATE TRIGGER … BEGIN … END; blocks intact.
    # IMPORTANT: re-append '\n' because each_line strips it.
    private def self.split_sql_script(sql : String) : Array(String)
      statements = [] of String
      buf = IO::Memory.new
      in_trigger = false

      sql.each_line do |line|
        stripped = line.rstrip

        # enter trigger block on CREATE TRIGGER
        if !in_trigger && stripped =~ /\A\s*CREATE\s+TRIGGER\b/i
          in_trigger = true
        end

        # re-append newline that each_line removed
        buf << line
        buf << '\n'

        if in_trigger
          # trigger ends at a line "END;" (case-insensitive; allow spaces)
          if stripped =~ /\A\s*END;?\s*\z/i
            statements << buf.to_s
            buf = IO::Memory.new
            in_trigger = false
          end
        else
          # normal statement ends with semicolon at line end
          if stripped.ends_with?(';')
            statements << buf.to_s
            buf = IO::Memory.new
          end
        end
      end

      # any trailing statement without a final ';'
      tail = buf.to_s.strip
      statements << tail unless tail.empty?

      statements
    end
  end
end
