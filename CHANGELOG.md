# Changelog

All notable changes to this project will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/).


## [Unreleased]
### Added
- **CLI Searcher**
  - Added `search` command
- Added CLI `show` command
- Added `Message.show`

### Changed
- (nothing yet)

### Fixed
- (nothing yet)


## [0.3.0] - 2025-09-08
### Added
- **CLI Importer**  
  - Added `import` command
  - Introduced `Messages.update_headers_from` helper
  - Introduced `Attachment.insert` helper
  - Implemented message archiving to `data/archive/yyyy-mm-dd`
  - Implemented bad message helper


## [0.2.0] - 2025-09-06
### Added
- **CLI Fetcher**  
  - Added `fetch` command with UIDL-based pipeline  
  - Supports conditional `DELE` only after successful spool + DB insert  
  - Introduced `Message.exists?` and `Message.insert_stub` helpers  
  - Implemented atomic spool write (`.part` → rename) to `spool/incoming/`


### Changed
- (nothing yet)

### Fixed
- (nothing yet)


## [0.1.0] - 2025-09-06
### Added
- Initial release

---

Copyright 2025 Chris Blunt  
Licensed under the Apache License, Version 2.0

---

[Unreleased]: https://github.com/chrisblunt-codes/mailarchiver/compare/v0.3.0...HEAD  
[0.3.0]: https://github.com/chrisblunt-codes/mailarchiver/releases/tag/v0.3.0
