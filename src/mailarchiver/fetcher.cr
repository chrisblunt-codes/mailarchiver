# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "pop3client"

require "./db"
require "./errors"
require "./models/account"

module MailArchiver
  class Fetcher
    def initialize(@account_name : String)
    end

    def run
      puts "Fetching... #{@account_name}"

      account : Account

      begin
        account = find_account
        fetch_mail(account) do |uid, message|
          puts "Fetched: #{uid}"
        end
      rescue ex : AccountNotFound
        puts "Error: Account not found: #{@account_name}"
        exit 65 # EX_DATAERR
      rescue ex : Pop3Client::ConnectionError
        puts "Error: #{ex.message}"
        exit 1
      rescue ex : Pop3Client::NotConnectedError
        puts "Error: POP3 client not connected"
        exit 1
      rescue ex : Pop3Client::ProtocolError
        puts "Error: #{ex.message}"
        exit 1
      end
    end

    private def find_account : Account
      begin
        sql = %q{
          SELECT
            id,
            name,
            host,
            port,
            username,
            password_cipher,
            password_iv,
            password_tag,
            key_version,
            use_tls,
            delete_after_fetch
          FROM accounts
          WHERE name = ?
        }

        row = DBA.db.query_one sql, @account_name,
          as: { Int64, String, String, Int32, String, Bytes, Bytes, Bytes, Int32, Int32, Int32 }

        Account.new(*row)
      rescue e : DB::NoResultsError
        raise AccountNotFound.new
      end
    end

    private def fetch_mail(account : Account, &block)
      client = Pop3Client::Client.new(account.host, account.port)
      client.connect
      client.login(account.username, account.password)

      client.uidl.each_with_index do |message_id, idx|
        msg_num = idx + 1
        message = client.retr(msg_num)
        yield message_id, message

        if account.delete_after_fetch
          client.dele(msg_num)
        end
      end

      client.quit
    ensure
      client.close if client
    end
  end
end
