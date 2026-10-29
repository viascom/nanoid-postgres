# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Each release links to its full release notes.

## Unreleased

### Added

- CI on GitHub Actions runs the full test matrix on every pull request and push to `main`, one job per PostgreSQL
  version.
- `nanoid()` and `nanoid_optimized()` carry the release version as their comment, readable with
  `obj_description('nanoid'::regproc, 'pg_proc')`.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue and pull request templates, and this changelog.
- README sections on the pgcrypto requirement, the supported PostgreSQL versions, installing a pinned release,
  reading the installed version, and uninstalling.

### Changed

- The license header in every source file is now the standard Apache License 2.0 notice. The license itself is
  unchanged.

## [3.0.0] - 2026-07-20

### Breaking

- The third parameter of `nanoid_optimized()` is the byte `cutoff` (`256 - (256 % length(alphabet))`) instead of the
  bit `mask`. Old mask values run without an error but produce wrong ids.
- `nanoid()` gains a fourth parameter, so the upgrade drops the `nanoid(int, text, float)` and `nanoid(int, text)`
  signatures. Column defaults that depend on them block the upgrade until they are dropped and re-added.

### Added

- The `prefix` parameter of `nanoid()` for typed ids such as `usr_...`.
- Alphabets with 256 symbols.

### Changed

- Random bytes are mapped with the safe-byte-cutoff algorithm from ai/nanoid v6, which rejects far fewer bytes for
  alphabets whose length does not divide 256 and supports single-symbol alphabets.
- The default additional bytes factor of `1.6` fits every alphabet.
- `nanoid.sql` runs in a single transaction: an upgrade either completes or leaves the previous installation intact.
- The test matrix pulls the latest minor of every major version and includes the PostgreSQL 19 prerelease.

### Fixed

- `nanoid_optimized()` raises an error instead of looping forever on non-positive or `NULL` inputs.

## [2.1.1] - 2026-07-13

### Fixed

- `nanoid()` and `nanoid_optimized()` are declared `PARALLEL UNSAFE`, which fixes
  `cannot start commands during a parallel operation` in parallel queries.
- `LEAKPROOF` is disabled by default on `nanoid_optimized()` as well.

### Added

- A Docker test suite for every PostgreSQL major version from 9.6 through 18, with regression tests for parallel
  queries.

## [2.1.0] - 2024-03-25

### Changed

- `LEAKPROOF` is disabled by default on `nanoid()`, so the function installs without superuser rights.

## [2.0.0] - 2023-09-01

### Added

- The `additionalBytesFactor` parameter of `nanoid()`, input validation, and `nanoid_optimized()`.

### Changed

- The step size is capped at 1024 bytes, the `gen_random_bytes()` limit.

## [1.0.0] - 2023-08-31

### Added

- `nanoid(size, alphabet)` built on pgcrypto.

[3.0.0]: https://github.com/viascom/nanoid-postgres/releases/tag/3.0.0
[2.1.1]: https://github.com/viascom/nanoid-postgres/releases/tag/2.1.1
[2.1.0]: https://github.com/viascom/nanoid-postgres/releases/tag/2.1.0
[2.0.0]: https://github.com/viascom/nanoid-postgres/releases/tag/2.0.0
[1.0.0]: https://github.com/viascom/nanoid-postgres/releases/tag/1.0.0
