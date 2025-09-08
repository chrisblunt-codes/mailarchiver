# Copyright 2025 Chris Blunt
# Licensed under the Apache License, Version 2.0

require "./spec_helper"

require "../src/mailarchiver/db"
require "../src/mailarchiver/searcher"

alias DBA      = MailArchiver::DBA
alias Searcher = MailArchiver::Searcher

module DBA
  @@db : DB::Database?
  def self.db : DB::Database
    @@db ||= DB.open "sqlite3::memory:"
  end
end

DBA.migrate!

describe "Search" do
  it "parse_query maps fields and operators safely" do
    q = %(from:alice and cc:bob or not urgent "keep this AND that")
    out = Searcher.parse_query(q)
    
    # Field names rewritten
    out.should contain("from_addr:alice")
    out.should contain("cc_addrs:bob")
    
    # Boolean uppercased, quoted phrase preserved
    out.should contain("AND")
    out.should contain("OR")
    out.should contain("NOT")
    out.should contain(%("keep this AND that")) # inner AND stays inside quotes
    
    # Does not break 'account:'
    Searcher.parse_query("account:xyz").should eq("account:xyz")

    # Unary minus -> NOT term
    Searcher.parse_query("-spam invoice").should contain("NOT spam")
    Searcher.parse_query("(-spam) invoice").should contain("(NOT spam)")
    Searcher.parse_query("from:alice -urgent").should contain("NOT urgent")
  end

   it "performs FTS search with bm25 ranking" do
    DBA.db.exec "INSERT INTO messages(id,account_id,uidl,sha256,path,received_at,subject,from_addr) VALUES (1,'default','aaa','shaa','patha','2025-04-01T10:00:00Z','Invoice April','billing@example.com')"
    DBA.db.exec "INSERT INTO messages(id,account_id,uidl,sha256,path,received_at,subject,from_addr) VALUES (2,'default','bbb','shab','pathb','2025-04-02T09:00:00Z','Party invite','friend@foo.com')"

    # 1) Full-text 'invoice' hits msg 1
    hits = Searcher.search("invoice")
    hits.size.should eq(1)
    hits.first.id.should eq(1_i64)

    # 2) Field mapping 'from:example.com'
    Searcher.parse_query("from:example.com").should eq(%(from_addr:"example com"))
    Searcher.parse_query("cc:bob-smith@acme.com").should contain(%(cc_addrs:"bob smith acme com"))
    hits = Searcher.search("from:example.com")
    hits.map(&.id).should eq([1_i64])

    # 3) Prefix 'inv*'
    hits = Searcher.search("subject:inv*")
    hits.map(&.id).should eq([2_i64, 1_i64])

    # 4) Prefix 'par*'
    hits = Searcher.search("subject:par*")
    hits.map(&.id).should eq([2_i64])
   end
end
