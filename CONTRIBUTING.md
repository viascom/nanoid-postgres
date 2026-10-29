# Contributing to nanoid-postgres

Contributions are welcome: bug reports, ideas, documentation fixes and code. By taking part you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

- **Questions** belong in [Discussions](https://github.com/viascom/nanoid-postgres/discussions).
- **Bugs and feature ideas** go into an [issue](https://github.com/viascom/nanoid-postgres/issues/new/choose).
  Issues labeled `good first issue` are a good place to start.
- **Security problems** must not go into a public issue; see [SECURITY.md](SECURITY.md).

## Development setup

All you need is Docker. The test suite starts the official PostgreSQL images, installs `nanoid.sql` and runs the unit
tests, the regression tests and an upgrade-path test from the previous release:

```bash
dev/test/run_tests.sh          # every supported major version (9.6 through 18 plus the 19 prerelease)
dev/test/run_tests.sh 17 18    # only the given versions, handy while iterating
```

The upgrade-path test installs `nanoid.sql` from `origin/main`, so fetch `main` before running it. CI runs the full
matrix on every pull request, one job per version.

`dev/benchmark/` holds an A/B harness: install two implementations as `a_nanoid()` and `b_nanoid()` and run
`benchmarks.sql` to compare them.

## Rules for changes

- **Supported versions.** `nanoid.sql` must install unchanged on every PostgreSQL major version from 9.6 on, including
  versions that reached end of life upstream. Use newer syntax or functions only with a fallback for older versions.
  Dropping a version is a breaking change and ships only in a major release.
- **Atomic, re-runnable script.** `nanoid.sql` runs in one transaction, and running it again upgrades an existing
  installation. Use `CREATE OR REPLACE FUNCTION`, and drop an old signature only when the signature changes.
- **Function declarations:** `VOLATILE` and `PARALLEL UNSAFE` (see issue #16), `LEAKPROOF` left commented out so the
  script installs without superuser rights.
- **Inputs are validated** with `RAISE EXCEPTION` in `nanoid()`. `nanoid_optimized()` is the exception and only keeps
  its termination guards.
- **Tests come with the change.** New behavior gets a unit test in `dev/test/unit_tests.sql`, a fix gets a section in
  `dev/test/regression_tests.sql` named after its issue that fails without the fix, and the full matrix has to pass.
- **Parity:** keep the behavior aligned with [nanoid-mysql-mariadb](https://github.com/viascom/nanoid-mysql-mariadb)
  and [nanoid-kotlin](https://github.com/viascom/nanoid-kotlin) and, where it makes sense for SQL, with
  [ai/nanoid](https://github.com/ai/nanoid). If a change only fits PostgreSQL, say why in the pull request.
- **Documentation:** update `README.md` for any user-visible change and add an entry under *Unreleased* in
  `CHANGELOG.md`.

## Commits and pull requests

- Open or pick an issue first, then branch as `<type>/<issue>-<short-name>`, e.g. `fix/12-null-prefix`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`,
  `test:`, `chore:`, with `!` for a breaking change (`feat!:`). Reference the issue in the subject (`#12`) and in the
  body with `Refs #12`.
- The pull request body says what changed and how you tested it, and ends with `Closes #12`.

## Releases (maintainers)

Versions follow [Semantic Versioning](https://semver.org/). A changed function signature, return type or error
behavior is a breaking change.

1. Bump the version in the two `COMMENT ON FUNCTION` lines at the end of `nanoid.sql` and move the *Unreleased*
   entries in `CHANGELOG.md` under the new version.
2. After the pull request is merged, tag the merge commit as `X.Y.Z` (no `v` prefix).
3. Publish a GitHub release titled `vX.Y.Z - <short summary>` with notes in the style of the earlier releases:
   breaking changes, new features, fixes, changes, verification and, for breaking releases, a migration guide.

## License

By contributing you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), the license
of this project.
