# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "openssl"

require "openssl/digest"

module MailArchiver
  module HMAC
    def self.digest(algorithm : Symbol, key : Bytes, data : Bytes | String) : Bytes
      digest = case algorithm
              when :sha256 then OpenSSL::Digest.new("SHA256")
              else
                raise "unsupported algo: #{algorithm}"
              end

      block_size = 64  # SHA256 block size
      key = key.dup
      if key.size > block_size
        key = digest.update(key).final
        digest.reset
      end
      key = key + Bytes.new(block_size - key.size, 0_u8) if key.size < block_size

      o_key_pad = key.map { |b| b ^ 0x5c }
      i_key_pad = key.map { |b| b ^ 0x36 }

      inner = digest.update(i_key_pad + data.to_slice).final
      digest.reset
      outer = digest.update(o_key_pad + inner).final
      digest.reset

      outer
    end
  end

  module Secrets
    # APP_KEY is base64 of 32 random bytes
    def self.current_key : Bytes
      b64 = ENV["APP_KEY"]? || raise "APP_KEY missing"
      Base64.decode(b64)
    end

    def self.current_key_version : Int32
      (ENV["APP_KEY_VERSION"]? || "1").to_i
    end

    # Derive two subkeys from master using HMAC-SHA256(labels)
    private def self.derive_keys(master : Bytes) : {enc: Bytes, mac: Bytes}
      enc = HMAC.digest(:sha256, master, "enc")
      mac = HMAC.digest(:sha256, master, "mac")
      {enc: enc, mac: mac} # 32 bytes each
    end

    def self.encrypt(plaintext : String) : {cipher: Bytes, iv: Bytes, tag: Bytes}
      master = current_key
      keys = derive_keys(master)
      iv = Random::Secure.random_bytes(16) # AES-CBC IV is 16 bytes

      c = OpenSSL::Cipher.new("aes-256-cbc")
      c.encrypt
      c.key = keys[:enc]
      c.iv  = iv
      ciphertext = c.update(plaintext.to_slice) + c.final

      # EtM: tag = HMAC-SHA256(mac_key, iv || ciphertext)
      io = IO::Memory.new
      io.write iv
      io.write ciphertext
      tag = HMAC.digest(:sha256, keys[:mac], iv + ciphertext)

      {cipher: ciphertext, iv: iv, tag: tag}
    end

    def self.decrypt(cipher : Bytes, iv : Bytes, tag : Bytes) : String
      master = current_key
      keys = derive_keys(master)

      # verify tag (EtM)
      io = IO::Memory.new
      io.write iv
      io.write cipher
      expected = HMAC.digest(:sha256, keys[:mac], io.to_slice)
      raise "auth failed" unless secure_compare(expected, tag)

      d = OpenSSL::Cipher.new("aes-256-cbc")
      d.decrypt
      d.key = keys[:enc]
      d.iv  = iv

      plaintext_bytes = d.update(cipher) + d.final
      String.new(plaintext_bytes)  # ← this yields "password", not "Bytes[...]"
    end

    # Constant-time compare
    private def self.secure_compare(a : Bytes, b : Bytes) : Bool
      return false unless a.size == b.size
      diff = 0_u8
      i = 0
      while i < a.size
        diff |= (a[i] ^ b[i])
        i += 1
      end
      diff == 0
    end
  end
end