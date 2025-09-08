-- ----------------------------------------------------------------------------------------------------
-- Enable foreign keys
-- ----------------------------------------------------------------------------------------------------
PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------------------------------
-- Accounts: POP3/IMAP credentials (password encrypted-at-rest)
-- ----------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS accounts (
  id                    INTEGER PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,   -- display name
  host                  TEXT NOT NULL,
  port                  INTEGER NOT NULL CHECK (port BETWEEN 1 AND 65535),
  username              TEXT NOT NULL,

  -- CBC+HMAC fields 
  password_cipher       BLOB NOT NULL,          -- ciphertext
  password_iv           BLOB NOT NULL,          -- 12-byte nonce
  password_tag          BLOB NOT NULL,          -- 16-byte auth tag
  key_version           INTEGER NOT NULL DEFAULT 1,

  use_tls               INTEGER NOT NULL DEFAULT 1 CHECK (use_tls IN (0,1)),
  delete_after_fetch    INTEGER NOT NULL DEFAULT 0 CHECK (delete_after_fetch IN (0,1)),
  created_at            TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- auto-update updated_at on any change (no recursion in SQLite)
DROP TRIGGER IF EXISTS trg_accounts_updated_at;
CREATE TRIGGER trg_accounts_updated_at
AFTER UPDATE ON accounts
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE accounts SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ----------------------------------------------------------------------------------------------------
-- Messages: one row per archived email
-- ----------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id                    INTEGER PRIMARY KEY,
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  uidl                  TEXT NOT NULL,        -- POP3 UIDL
  size_octets           INTEGER,
  received_at           TEXT,                 -- RFC822 Date parsed → ISO8601
  subject               TEXT,
  from_addr             TEXT,
  to_addrs              TEXT,
  cc_addrs              TEXT,
  message_id            TEXT,
  sha256                TEXT NOT NULL UNIQUE, -- of raw .eml
  path                  TEXT NOT NULL,        -- relative path to .eml
  created_at            TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_account_uidl ON messages(account_id, uidl);
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_path         ON messages(path);
CREATE INDEX IF NOT EXISTS idx_messages_received_at         ON messages(received_at);
CREATE INDEX IF NOT EXISTS idx_messages_account_id          ON messages(account_id);
CREATE INDEX IF NOT EXISTS idx_messages_acct_received       ON messages(account_id, received_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_account_uidl ON messages(account_id, uidl);
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_sha256       ON messages(sha256);

-- ----------------------------------------------------------------------------------------------------
-- FTS5 (external-content): headers only (subject/from/to/cc/message_id)
-- stays in sync via triggers
-- ----------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS fts_messages;
CREATE VIRTUAL TABLE fts_messages USING fts5(
  subject,
  from_addr,
  to_addrs,
  cc_addrs,
  message_id,
  content='messages',
  content_rowid='id',
  tokenize='porter'
);

DROP TRIGGER IF EXISTS fts_messages_ai;
CREATE TRIGGER fts_messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO fts_messages(rowid, subject, from_addr, to_addrs, cc_addrs, message_id)
  VALUES (new.id, new.subject, new.from_addr, new.to_addrs, new.cc_addrs, new.message_id);
END;

DROP TRIGGER IF EXISTS fts_messages_ad;
CREATE TRIGGER fts_messages_ad AFTER DELETE ON messages BEGIN
  INSERT INTO fts_messages(fts_messages, rowid, subject, from_addr, to_addrs, cc_addrs, message_id)
  VALUES('delete', old.id, old.subject, old.from_addr, old.to_addrs, old.cc_addrs, old.message_id);
END;

DROP TRIGGER IF EXISTS fts_messages_au;
CREATE TRIGGER fts_messages_au AFTER UPDATE ON messages BEGIN
  INSERT INTO fts_messages(fts_messages, rowid, subject, from_addr, to_addrs, cc_addrs, message_id)
  VALUES('delete', old.id, old.subject, old.from_addr, old.to_addrs, old.cc_addrs, old.message_id);
  INSERT INTO fts_messages(rowid, subject, from_addr, to_addrs, cc_addrs, message_id)
  VALUES (new.id, new.subject, new.from_addr, new.to_addrs, new.cc_addrs, new.message_id);
END;

-- ----------------------------------------------------------------------------------------------------
-- Attachments metadata (no extraction required yet)
-- ----------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attachments (
  id                    INTEGER PRIMARY KEY,
  message_id            INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  filename              TEXT,                   -- from Content-Disposition / Content-Type
  content_type          TEXT,                   -- e.g. application/pdf
  size_octets           INTEGER,                -- decoded size if/when extracted; else NULL
  sha256                TEXT CHECK (sha256 IS NULL OR length(sha256) = 64), -- decoded bytes hash
  path                  TEXT,                   -- relative filesystem path if extracted later
  created_at            TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_attachments_message_id    ON attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_attachments_filename      ON attachments(filename);
CREATE INDEX IF NOT EXISTS idx_attachments_sha256        ON attachments(sha256)
CREATE UNIQUE INDEX IF NOT EXISTS idx_attachments_msg_fn ON attachments(message_id, filename);

-- tiny FTS for attachment filenames (external-content, auto-sync)
DROP TABLE IF EXISTS fts_attachments;
CREATE VIRTUAL TABLE fts_attachments USING fts5(
  filename,
  content='attachments',
  content_rowid='id'
);

DROP TRIGGER IF EXISTS fts_attachments_ai;
CREATE TRIGGER fts_attachments_ai AFTER INSERT ON attachments BEGIN
  INSERT INTO fts_attachments(rowid, filename)
  VALUES (new.id, new.filename);
END;

DROP TRIGGER IF EXISTS fts_attachments_ad;
CREATE TRIGGER fts_attachments_ad AFTER DELETE ON attachments BEGIN
  INSERT INTO fts_attachments(fts_attachments, rowid, filename)
  VALUES('delete', old.id, old.filename);
END;

DROP TRIGGER IF EXISTS fts_attachments_au;
CREATE TRIGGER fts_attachments_au AFTER UPDATE ON attachments BEGIN
  -- delete old row
  INSERT INTO fts_attachments(fts_attachments, rowid, filename)
  VALUES('delete', old.id, old.filename);
  -- insert new row
  INSERT INTO fts_attachments(rowid, filename)
  VALUES (new.id, new.filename);
END;