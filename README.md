# mailarchiver

A lightweight Crystal application that fetches, indexes, and archives email messages via POP3.  
It stores messages as `.eml` files and indexes headers in SQLite with FTS5 for fast search.


## Usage

TBC

## Roadmap

- [x] Basic POP3 client integration (via `pop3client` shard)
- [x] CLI fetcher command with UIDL-based pipeline
- [x] Atomic spool writes (`.part` → rename)

- [x] Importer command  
  - Parse message headers (From, To, Cc, Date, Subject, Message-Id)  
  - Enrich SQLite index with metadata  
  - Move `.eml` files from `spool/incoming` into structured archive folders (`archive/YYYY/MM/DD/`)

- [x] Duplicate handling & resilience  
  - Enforce unique `(account_id, uidl)` and `sha256`  
  - Skip already imported messages gracefully  
  - Safe resume after crash

- [x] Search & reporting  
  - Implement CLI search command using SQLite FTS5  
  - Show matches with basic metadata (date, from, subject)  

- [x] Show messages
  - Option to show `.eml` formatted as plain  text (or as JSON)

### Next
- [ ] Configuration & CLI improvements  
  - More options to manage accounts  
  - Verbosity/logging flags  
  - Exit codes aligned with UNIX conventions

- [ ] Packaging & distribution  
  - Prebuilt binaries (Linux/Windows)  

### Future ideas
- [ ] IMAP support (optional)  
- [ ] Web UI for browsing/searching messages  
- [ ] Export to mbox/mboxrd for interoperability  
- [ ] Simple REST API for integration with other tools


## Contributing

1. Fork it (<https://github.com/chrisblunt-codes/mailarchiver/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Chris Blunt](https://github.com/chrisblunt-codes) - creator and maintainer


## License

Copyright 2025 Chris Blunt
Licensed under the Apache License, Version 2.0
SPDX-License-Identifier: Apache-2.0

