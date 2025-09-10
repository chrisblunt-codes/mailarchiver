# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "json"

require "dotenv"
require "option_parser"

require "./mailarchiver/*"

Dotenv.load

module MailArchiver
  VERSION = "0.2.0"

  module CLI
    def self.run
      command = ARGV.shift?

      case command
      when "init"         then handle_init
      when "add-account"  then handle_add_account
      when "fetch"        then handle_fetch
      when "import"       then handle_import
      when "search"       then handle_search
      when "show"         then handle_show    
      when nil            then usage("no command")
      else                    
        usage("unknown command: #{command}")
      end
    end

    def self.handle_init
      DBA.migrate!
      puts "DB ready"
    end

    def self.handle_add_account
      name = "default"
      host = "127.0.0.1"
      port = 110
      user = "user"
      tls  = false
      dele = false
      password : String? = nil
      pw_stdin = false

      OptionParser.parse(ARGV) do |p|
        p.on("--name=NAME", "Account name")   { |v| name = v }
        p.on("--host=HOST", "POP3 host")      { |v| host = v }
        p.on("--port=PORT", "POP3 port")      { |v| port = v.to_i }
        p.on("--user=USER", "Username")       { |v| user = v }
        p.on("--password=PASS",  "Password (not recommended)") { |v| password = v }
        p.on("--password-stdin", "Read password from stdin")   { pw_stdin = true }
        p.on("--tls", "Enable TLS")           { tls = true }
        p.on("--no-tls", "Disable TLS")       { tls = false }
        p.on("--delete", "DELE after fetch")  { dele = true }
        p.on("--no-delete", "Do not DELE")    { dele = false }
      end
          
      if pw_stdin
        puts "Enter password: "
        password = STDIN.gets.try &.chomp
      end

      if password.nil?
        STDERR.puts "No password provided. Use --password or --password-stdin."
        exit 65 # EX_DATAERR
      end

      encrypted = Secrets.encrypt(password.not_nil!)

      begin
        res = DBA.db.exec %q(
                INSERT INTO accounts(name, host, port, username, password_cipher, password_iv, password_tag, use_tls, delete_after_fetch)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              ), name, host, port, user, encrypted[:cipher], encrypted[:iv], encrypted[:tag], (tls ? 1 : 0), (dele ? 1 : 0)
       id = res.last_insert_id
        puts "Account added (id=#{id})"
      rescue e : SQLite3::Exception 
        puts "Error: #{e.message}"
      end
    end

    def self.handle_fetch
      name = "default"

      OptionParser.parse(ARGV) do |p|
        p.on("--name=NAME", "Account Name")   { |v| name = v }
      end

      Fetcher.new(account_name: name).run
      puts "Fetch complete."
    end

    def self.handle_import
      Importer.new.run
      puts "Import complete."
    end

    def self.handle_search
      files   = false
      limit   = 50
      offset  = 0
      since   : String? = nil
      until_  : String? = nil
      sort    = "rank"
      json    = false

      parser = OptionParser.parse(ARGV) do |p|
        p.banner = "Usage: mailarchiver search [options] <query>"
        p.on("--files", "--attachments", "Search attachment filenames") { files = true }
        p.on("--limit N", "Limit (default 50)") { |v| limit = v.to_i }
        p.on("--offset N", "Offset (default 0)") { |v| offset = v.to_i }
        p.on("--since DATE", "Filter received_at >= DATE (YYYY-MM-DD)") { |v| since = v }
        p.on("--until DATE", "Filter received_at <= DATE (YYYY-MM-DD)") { |v| until_ = v }
        p.on("--sort SORT", "rank|date (default rank)") { |v| sort = v }
        p.on("--json", "Output JSON") { json = true }
        p.on("-h", "--help", "Show help") { puts p; exit 0 }
      end

      query = ARGV.join(" ").strip
      if query.empty?
        STDERR.puts "search: missing <query>\n\n#{parser}"
        exit 2
      end
      
      if files
        search_files(query, limit, offset, json)
      else
        search_messages(query, limit, offset, since, until_, sort, json)
      end
    end

    def self.handle_show
      msg_num : Int64 = 0
      json = false

      parser = OptionParser.parse(ARGV) do |p|
        p.banner = "Usage: mailarchiver show [options] <msg_num>"
        p.on("--json", "Output JSON") { json = true }
        p.on("-h", "--help", "Show help") { puts p; exit 0 }
      end
      
      if ARGV.empty?
        STDERR.puts "show: invalid <msg_num>\n\n#{parser}"
        exit 2
      else
        msg_num = ARGV[0].to_i64 rescue 0_i64
      end

      Message.show(msg_num, json)
    end

    def self.usage(msg : String)
      STDERR.puts msg
      STDERR.puts "Usage: mailarchiver <init|add-account|fetch|import|search|show|attachments>"
      exit 64 # EX_USAGE
    end

    # ---------------------------------------------------------------------
    # Search commands
    # ---------------------------------------------------------------------
    
    private def self.search_files(query : String, limit : Int32, offset : Int32, json : Bool)
      hits = Searcher.search_attachments(query, limit, offset)

      if json
        puts hits.map { |h|
          {
            id: h.id, received_at: h.received_at, from_addr: h.from_addr,
            subject: h.subject, filename: h.filename, rank: h.rank
          }
        }.to_json
      else
        hits.each do |h|
          puts "#{h.received_at}  [#{h.id}]  #{h.from_addr}  #{h.subject}  (#{h.filename})"
        end
      end
    end

    private def self.search_messages(query : String, limit : Int32, offset : Int32, since : String?, until_ : String?, sort : String, json : Bool )
      hits = Searcher.search(query, limit, offset)

      # optional date filter
      hits = hits.select { |h|
        (since.nil?  || (h.received_at && h.received_at.not_nil! >= "#{since}")) &&
        (until_.nil? || (h.received_at && h.received_at.not_nil! <= "#{until_}"))
      }

      hits =  case sort
              when "date" then hits.sort_by { |h| h.received_at || "" }.reverse
              else hits # already bm25 rank
              end

      if json
        puts hits.map { |h|
          { id: h.id, received_at: h.received_at, from_addr: h.from_addr,
            subject: h.subject, rank: h.rank }
        }.to_json
      else
        hits.each do |h|
          puts "#{h.received_at}  [#{h.id}]  #{h.from_addr}  #{h.subject}"
        end
      end
    end
  end
end

MailArchiver::CLI.run
