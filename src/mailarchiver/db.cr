# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "db"
require "sqlite3"

module Mailarchiver
  module DBA
    @@db : DB::Database?

    def self.db : DB::Database
      @@db ||= DB.open(ENV["ARCHIVE_DB"]? || "sqlite3:./data/mailarchiver.db")
    end

    def self.migrate!
      sql = File.read("./db/migrate.sql")

      stmts = sql
              .split(/;[ \t]*\n/)
              .map(&.strip)
              .reject(&.empty?)

      db.transaction do |tx|
        stmts.each do |s|
          tx.connection.exec s
        end
      end
    end
  end
end
