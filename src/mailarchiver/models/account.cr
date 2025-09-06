# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "../secrets"

module MailArchiver
  class Account
    getter id : Int64
    getter name : String
    getter host : String
    getter port : Int32
    getter username : String
    getter use_tls : Bool
    getter delete_after_fetch : Bool
    getter key_version : Int32

    # encrypted-at-rest fields
    getter password_cipher : Bytes
    getter password_iv     : Bytes
    getter password_tag    : Bytes

    def initialize(@id : Int64,
                   @name : String,
                   @host : String,
                   @port : Int32,
                   @username : String,
                   password_cipher : Bytes,
                   password_iv     : Bytes,
                   password_tag    : Bytes,
                   key_version     : Int32,
                   use_tls_i       : Int32,
                   delete_i        : Int32)
      @password_cipher = password_cipher
      @password_iv     = password_iv
      @password_tag    = password_tag
      @key_version     = key_version
      @use_tls         = use_tls_i == 1
      @delete_after_fetch = delete_i == 1
    end

    # Decrypt only when needed
    def password : String
      Secrets.decrypt(@password_cipher, @password_iv, @password_tag)
    end

    def to_s(io : IO)
      io << "Account(id=#{id}, host=#{host}, user=#{username}, tls=#{use_tls}, delete=#{delete_after_fetch})"
    end
  end
end
