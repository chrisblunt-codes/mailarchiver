-- messages: one row per archived email
CREATE TABLE IF NOT EXISTS messages (
  id           INTEGER PRIMARY KEY,
  account_id   INTEGER NOT NULL,
  uidl         TEXT NOT NULL,        -- POP3 UIDL
  msg_num      INTEGER,              -- POP3 message number when fetched
  size_octets  INTEGER,
  received_at  TEXT,                 -- RFC822 Date parsed → ISO8601
  subject      TEXT,
  from_addr    TEXT,
  to_addrs     TEXT,
  cc_addrs     TEXT,
  message_id   TEXT,
  sha256       TEXT NOT NULL UNIQUE, -- of raw .eml
  path         TEXT NOT NULL,        -- relative path to .eml
  created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_account_uidl ON messages(account_id, uidl);
CREATE INDEX IF NOT EXISTS idx_messages_received_at ON messages(received_at);

-- accounts: where to pull from
CREATE TABLE IF NOT EXISTS accounts (
  id             INTEGER PRIMARY KEY,
  name           TEXT NOT NULL UNIQUE,  -- display name
  host           TEXT NOT NULL,
  port           INTEGER NOT NULL,
  username       TEXT NOT NULL,
  password_enc   TEXT NOT NULL,         -- or an env var name / keyring ref
  use_tls        INTEGER NOT NULL DEFAULT 1,
  delete_after_fetch INTEGER NOT NULL DEFAULT 0, -- if you want DELE
  created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- FTS5: headers only to start (subject/from/to/cc/message_id)
CREATE VIRTUAL TABLE IF NOT EXISTS fts_messages USING fts5(
  subject,
  from_addr,
  to_addrs,
  cc_addrs,
  message_id,
  content='',
  tokenize = 'porter'                  -- or 'unicode61'
);

-- convenient shadow table to map FTS rows to message ids
CREATE TABLE IF NOT EXISTS fts_messages_docids (
  rowid      INTEGER PRIMARY KEY,  -- equals fts rowid
  message_id INTEGER NOT NULL REFERENCES messages(id)
);

-- attachments metadata (no extraction required yet)
CREATE TABLE IF NOT EXISTS attachments (
  id           INTEGER PRIMARY KEY,
  message_id   INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  filename     TEXT,                 -- from Content-Disposition / Content-Type
  content_type TEXT,                 -- e.g. application/pdf
  transfer_enc TEXT,                 -- base64 / quoted-printable / 7bit / 8bit
  size_octets  INTEGER,              -- decoded size if/when extracted; else NULL
  sha256       TEXT,                 -- of decoded bytes if extracted or inlined later
  path         TEXT,                 -- relative filesystem path if extracted later
  created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_attachments_msg ON attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_attachments_ext ON attachments(filename);

-- tiny FTS just for filenames (fast lookups like *.pdf, “invoice”, etc.)
CREATE VIRTUAL TABLE IF NOT EXISTS fts_attachments USING fts5(
  filename,
  content=''
);

-- map FTS row to attachments.id (same trick as messages)
CREATE TABLE IF NOT EXISTS fts_attachments_docids (
  rowid        INTEGER PRIMARY KEY,
  attachment_id INTEGER NOT NULL REFERENCES attachments(id)
);
