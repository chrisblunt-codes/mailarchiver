# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "file_utils"

require "crystal-mime"

require "./db"
require "./errors"
require "./models/account"
require "./models/message"
require "./models/attachment"


module MailArchiver
  class Importer

    DATA_ROOT    = "data"
    ARCHIVE_PATH = File.join(DATA_ROOT, "archive")
    BAD_MSG_PATH = File.join(DATA_ROOT, "spool", "bad")

    def run(limit : Int32 = 500)
      # Pull messages that haven't been updated (enriched) yet (subject still NULL)
      rows = pending_message_rows

      rows.each do |row|
        id, path = row[0], row[1]

        puts path
        if File.exists?(path)
          begin
            email = load_email(path)
            
            puts "IMPORTING: #{id} (#{path})"
            if Message.update_headers_from(id, email)
              Attachment.insert(id, email)
              archive_message(id, path)
            else
              handle_bad_message(id, path)
              next
            end
          rescue ex
            STDERR.puts "Error: failed to import id=#{id} (#{path}): #{ex.message}"
            handle_bad_message(id, path)
            next
          end
        end
      end
    end

    # ------------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------------
    
    private def pending_message_rows
      DBA.db.query_all <<-SQL, as: {Int64, String}
        SELECT id, path
        FROM messages
        WHERE subject IS NULL
      SQL
    end

    private def load_email(path : String) 
      raw = File.read(path)
      MIME.mail_object_from_raw(raw)
    end

    private def handle_bad_message(id : Int64, path : String) : String
      eml_file = File.basename(path)
      bad_path = File.join(BAD_MSG_PATH, eml_file)       

      move_message(id, path, bad_path)
      bad_path
    end

    private def archive_message(id : Int64, path : String) : String
      eml_file = File.basename(path)
      arc_path = File.join(ARCHIVE_PATH, Time.utc.to_s("%Y-%m-%d"), eml_file)       

      move_message(id, path, arc_path)
      arc_path
    end

    private def move_message(id : Int64, src_path : String, dst_path : String)
      FileUtils.mkdir_p(File.dirname(dst_path))
      FileUtils.mv(src_path, dst_path)
      Message.update_path(id, path: dst_path)
    end
  end
end
