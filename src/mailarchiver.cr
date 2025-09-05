# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "option_parser"

require "./mailarchiver/*"

module MailArchiver
  VERSION = "0.1.0"

  module CLI
    def self.run
      command = ARGV.shift?

      case command
      when "init"         then handle_init
      when "add-account"  then handle_add_account
      when "fetch"        then handle_fetch
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

      begin
        res = DBA.db.exec %q(
                INSERT INTO accounts(name, host, port, username, password_enc, use_tls, delete_after_fetch)
                VALUES (?, ?, ?, ?, ?, ?, ?)
              ), name, host, port, user, password, (tls ? 1 : 0), (dele ? 1 : 0)

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

    def self.usage(msg : String)
      STDERR.puts msg
      STDERR.puts "Usage: mailarchiver <init|add-account|fetch|search|show|attachments>"
      exit 64 # EX_USAGE
    end
  end
end

MailArchiver::CLI.run
