# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "digest/sha256"
require "file_utils"

require "../utils"

module MailArchiver
  class Message
    def self.exists?(account_id : Int64, uidl : String) : Bool
      sql = "SELECT 1 FROM messages WHERE account_id = ? AND uidl = ? LIMIT 1"
      DBA.db.query_one?(sql, account_id, uidl, as: Int32).is_a?(Int32)
    end

    def self.insert_stub(
      account_id : Int64,
      uidl : String,
      sha256 : String,
      size_octets : Int64,
      rel_path : String,
      msg_num : Int32? = nil
    ) : Nil
      sql = %q{
        INSERT INTO messages (account_id, uidl, msg_num, size_octets, sha256, path, created_at)
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      }
      DBA.db.exec sql, account_id, uidl, msg_num, size_octets, sha256, rel_path
    end
    
    def self.write_to_spool(message : String) : { String, Int64, String }
      raw   = message.to_slice
      sha   = Digest::SHA256.hexdigest(raw)
      bytes = raw.size.to_i64

      dir = File.join("data", "spool", "incoming")
      FileUtils.mkdir_p(dir)

      final = File.join(dir, "#{sha}.eml")
      temp  = final + ".part"

      File.open(temp, "w") do |f|
        f.write(raw)
        f.flush
        begin
          f.fsync
        rescue
          # fsync may not be supported on some FS; ignore if it raises
        end
      end

      File.rename(temp, final)

      rel_path = Path[Utils.new_relative_path(final)].to_s
      {sha, bytes, rel_path}
    rescue ex
      raise SpoolingError.new(ex.message)
    end
  end
end
