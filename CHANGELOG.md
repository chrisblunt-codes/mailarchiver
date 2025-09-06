# Changelog

All notable changes to this project will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/).


## [Unreleased]
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

---

Copyright 2025 Chris Blunt  
Licensed under the Apache License, Version 2.0

---

[Unreleased]: https://github.com/chrisblunt-codes/mailarchiver/compare/v0.1.0...HEAD  
[0.1.0]: https://github.com/chrisblunt-codes/mailarchiver/releases/tag/v0.1.0
