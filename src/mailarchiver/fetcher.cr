# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "pop3client"

require "./db"
require "./errors"

module MailArchiver

  struct Account
    getter id                 : Int64
    getter host               : String
    getter port               : Int32
    getter username           : String
    getter password_enc       : String
    getter use_tls            : Bool
    getter delete_after_fetch : Bool

    def initialize(@id : Int64, @host : String, @port : Int32, @username : String,
                  @password_enc : String, use_tls : Int32, delete_after_fetch : Int32)

      @use_tls = use_tls == 1
      @delete_after_fetch = delete_after_fetch == 1
    end

    def initialize(@id : Int64, @host : String, @port : Int32, @username : String,
                   @password_enc : String, @use_tls : Bool, @delete_after_fetch : Bool)
    end

    def to_s(io : IO)
      io << "Account(id=#{id}, host=#{host}, user=#{username}, tls=#{use_tls}, delete=#{delete_after_fetch})"
    end
  end

  class Fetcher
    def initialize(@account_name : String)
    end

    def run
      puts "Fetching... #{@account_name}"

      begin
        account = find_account
      rescue e : AccountNotFound
        puts "Account not found: #{@account_name}"
        exit 1
      end
    end

    private def find_account : Account
      begin
        account = DBA.db.query_one %q(
                    SELECT id, host, port, username, password_enc, use_tls, delete_after_fetch
                    FROM accounts
                    WHERE name = ?
                  ), @account_name, as: { Int64, String, Int32, String, String, Int32, Int32 } 
        
        Account.new(*account)
      rescue e : DB::NoResultsError
        raise AccountNotFound.new
      end
    end
  end
end
