# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

module MailArchiver
  module Utils
    # Helper to turn an absolute path under project into a DB-relative path
    def self.new_relative_path(abs : String) : String
      # store paths relative to project root
      Path[abs].relative_to(Path[Dir.current]).to_s
    rescue
      abs
    end
  end
end
