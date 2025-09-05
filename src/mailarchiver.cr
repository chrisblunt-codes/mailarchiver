# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "./mailarchiver/*"

module Mailarchiver
  VERSION = "0.1.0"

  module CLI
    def self.run
      command = ARGV.shift?

      case command
      when "init"
        DBA.migrate!
        puts "DB ready."
      end
    end
  end
end

Mailarchiver::CLI.run
