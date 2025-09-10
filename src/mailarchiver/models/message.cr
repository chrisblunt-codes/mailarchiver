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
      account_id  : Int64,
      uidl        : String,
      sha256      : String,
      size_octets : Int64,
      rel_path    : String,
    ) : Nil
      sql = %q{
        INSERT INTO messages (account_id, uidl, size_octets, sha256, path, created_at)
        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      }
      DBA.db.exec sql, account_id, uidl, size_octets, sha256, rel_path
    end
    
    def self.show(message_row_id : Int64, json : Bool) : Nil
      email = find(message_row_id)

      if email
        if json
          headers =  email.headers
          if email.attachments.size > 0
            attachments = email.attachments.map { |a| "#{a.filename} (#{a.data.size})" }
            headers["Attachments"] = attachments.join(", ")
          end

          puts headers.to_json
        else
          puts "Date:    #{h(email, "Date")}"
          puts "From:    #{h(email, "From")}"
          puts "To:      #{h(email, "To")}"
          puts "Subject: #{h(email, "Subject")}"
          puts "MSG-ID:  #{h(email, "Message-ID")}"

          if email.attachments.size > 0
            puts "\nAttachments:"
            puts email.attachments.map { |a| "#{a.filename} (#{a.data.size})" }.join("\n")
          end
          puts "\n\n#{email.body_text}"
        end
      end
    end

    def self.find(message_row_id : Int64) : MIME::Email?  
      sql  = "SELECT path FROM messages WHERE id = ? LIMIT 1"
      path = DBA.db.query_one?(sql, message_row_id, as: String)

      if path && File.exists?(path)
        raw = File.read(path)
        MIME.mail_object_from_raw(raw)
      end
    end

    def self.update_headers_from(message_row_id : Int64, email : MIME::Email) : Bool
      received_at = parse_received_time(email)

      sql = <<-SQL
        UPDATE messages
        SET received_at = ?,
            subject     = ?,
            from_addr   = ?,
            to_addrs    = ?,
            cc_addrs    = ?,
            message_id  = ?
        WHERE id = ?
      SQL

      res = DBA.db.exec sql,
        iso8601_or_nil(received_at),
        h(email, "Subject"),
        h(email, "From"),
        h(email, "To"),
        h(email, "Cc"),
        h(email, "Message-ID"),
        message_row_id

      res.rows_affected > 0
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

    def self.update_path(message_row_id : Int64, path : String) : Nil
      sql = "UPDATE messages SET path = ? WHERE id = ?"
      DBA.db.exec sql, path, message_row_id
    end

    # ------------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------------
    
    private def self.h(email : MIME::Email, key : String) : String?
      email.headers[key]? || ""
    end

    private def self.parse_received_time(email : MIME::Email) : Time?
      if s = email.headers["Date"]?
        parse_rfc2822_or_3339(s)
      elsif r = email.headers["Received"]?
        if idx = r.rindex(';')
          parse_rfc2822_or_3339(r[(idx + 1)..-1].strip)
        else
          nil
        end
      else
        nil
      end
    end

    private def self.parse_rfc2822_or_3339(s : String) : Time?
      return Time::Format::RFC_2822.parse(s) rescue (Time::Format::RFC_3339.parse(s) rescue nil)
    end

    private def self.iso8601_or_nil(t : Time?) : String?
      t ? t.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ") : nil
    end
  end
end
