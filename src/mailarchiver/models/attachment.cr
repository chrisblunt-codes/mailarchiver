# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "digest/sha256"

require "../utils"

module MailArchiver
  class Attachment
    def self.insert(message_id : Int64, email : MIME::Email)
      return if email.attachments.empty?

      email.attachments.each do |a|
        filename = a.filename
        next if filename.nil?

        sha = Digest::SHA256.hexdigest(a.data)
        ctp = a.content_type

        sql = %q{
          INSERT INTO attachments (message_id, filename, content_type, size_octets, sha256)
          VALUES (?, ?, ?, ?, ?)
        }
        DBA.db.exec sql, message_id, filename, ctp, a.data.size, sha
      end
    end
  end
end
