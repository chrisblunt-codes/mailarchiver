# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "./db"

module MailArchiver
  struct SearchHit
    getter id           : Int64
    getter received_at  : String?
    getter from_addr    : String?
    getter subject      : String?
    getter message_id   : String?
    getter rank         : Float64

    def initialize(@id, @received_at, @from_addr, @subject, @message_id, @rank)
    end
  end

  struct AttachmentHit
    getter id           : Int64
    getter received_at  : String?
    getter from_addr    : String?
    getter subject      : String?
    getter filename     : String?
    getter rank         : Float64

    def initialize(@id, @received_at, @from_addr, @subject, @filename, @rank)
    end
  end

  class Searcher
    # Headers search via FTS5 + bm25 ranking.
    # Accepts user query in friendly syntax ("from:alice inv* -spam")
    def self.search(query : String, limit : Int32 = 50, offset : Int32 = 0) : Array(SearchHit)
      q = parse_query(query)

      sql = <<-SQL
        SELECT m.id,
               m.received_at,
               m.from_addr,
               m.subject,
               m.message_id,
               bm25(fts_messages) AS rank
        FROM fts_messages
        JOIN messages m ON m.id = fts_messages.rowid
        WHERE fts_messages MATCH ?
        ORDER BY rank, m.received_at DESC
        LIMIT ? OFFSET ?
      SQL

      rows = DBA.db.query_all(sql, q, limit, offset, as: {Int64, String?, String?, String?, String?, Float64})
      rows = rows.map { |row| SearchHit.new(*row) }
      rows
    end

    # Attachment filename search via FTS5. (No field scoping—just filenames.)
    def self.search_attachments(query : String, limit : Int32 = 50, offset : Int32 = 0) : Array(AttachmentHit)
      q = normalize_filename_query(query)
      sql = <<-SQL
        SELECT m.id,
               m.received_at,
               m.from_addr,
               m.subject,
               a.filename,
               bm25(fts_attachments) AS rank
        FROM fts_attachments
        JOIN attachments a ON a.id = fts_attachments.rowid
        JOIN messages m    ON m.id = a.message_id
        WHERE fts_attachments MATCH ?
        ORDER BY rank, m.received_at DESC
        LIMIT ? OFFSET ?
      SQL

      rows = DBA.db.query_all(sql, q, limit, offset, as: {Int64, String?, String?, String?, String?, Float64})
      rows = rows.map { |row| AttachmentHit.new(*row) }
      rows
    end

    # KISS parser: maps user-friendly fields to FTS columns, uppercases boolean ops,
    # preserves quoted phrases, and turns "-term" into "NOT term".
    def self.parse_query(q : String) : String
      parts = q.split('"')
      parts.each_with_index.map do |seg, i|
        if i.odd?
          %("#{seg.gsub(/"/, "\"\"")}")                    # keep quoted phrases
        else
          s = seg
            .gsub(/\s+/, " ").strip
            # field aliases (safe word-boundaries)
            .gsub(/\bfrom:/i,    "from_addr:")
            .gsub(/\bto:/i,      "to_addrs:")
            .gsub(/\bcc:/i,      "cc_addrs:")
            .gsub(/\bsubject:/i, "subject:")
            .gsub(/\bmessage_id:/i, "message_id:")
            # boolean ops uppercased
            .gsub(/\b(and|or|not)\b/i) { |m| m.upcase }
            # unary minus -> NOT <term>
            .gsub(/(^|[\s(])-(\w+)/, "\\1NOT \\2")

          # normalize fielded values with punctuation into phrases
          # e.g. from_addr:example.com -> from_addr:"example com"
          s = s.gsub(/\b(from_addr|to_addrs|cc_addrs|subject|message_id):([^\s)]+)/i) do
            field = $~[1]
            val   = $~[2]
            
            # leave simple words and prefixes like ali* alone
            if val =~ /\A[[:alnum:]]+\*?\z/
              "#{field}:#{val}"
            else
              cleaned = val.gsub(/[^[:alnum:]]+/, " ").strip
              %(#{field}:"#{cleaned}")
            end
          end

          s
        end
      end.join
    end


    def self.count(query : String) : Int64
      DBA.db.query_one("SELECT count(*) FROM fts_messages WHERE fts_messages MATCH ?", query, as: Int64)
    end

    def self.normalize_filename_query(q : String) : String
      s = q.strip
      # If it contains any non-alphanumeric char, turn it into a phrase
      if /[^[:alnum:]]/.match(s)
        %("#{s.gsub(/[^[:alnum:]]+/, " ").strip}")
      else
        s
      end
    end
  end
end
