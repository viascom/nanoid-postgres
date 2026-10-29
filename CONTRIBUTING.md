# Contributing to nanoid-postgres

## Before you start

- **Bugs and feature ideas:** open an [issue](https://github.com/viascom/nanoid-postgres/issues/new/choose) first, so we
  can agree on the approach before you write code.
- **Questions:** ask in [Discussions](https://github.com/viascom/nanoid-postgres/discussions).
- **Security issues:** follow [SECURITY.md](SECURITY.md); never open a public issue.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

The whole project is `nanoid.sql`. The tests need Docker and Bash; they install `nanoid.sql` into the official
PostgreSQL images and run `dev/test/unit_tests.sql`, `dev/test/regression_tests.sql` and an upgrade test against
each of them:

```bash
dev/test/run_tests.sh          # every supported version
dev/test/run_tests.sh 17 18    # only the given versions
```

The same suite runs in GitHub Actions on every pull request.

## Making a change

- `nanoid.sql` must keep installing on PostgreSQL 9.6. Use newer syntax or functions only with a fallback for older
  versions; the test matrix covers 9.6 through the latest prerelease.
- The script must stay atomic and re-runnable: it runs in one transaction, and running it again upgrades an existing
  installation. Drop an old function signature only when the signature changes.
- Add tests with every change: function behavior goes into `dev/test/unit_tests.sql`, a fixed bug gets its own
  section in `dev/test/regression_tests.sql` named after the issue.
- When you port behavior from [ai/nanoid](https://github.com/ai/nanoid), link the upstream release or commit.
- Commit messages and pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/) and end
  with the issue number, for example `feat: support 256-symbol alphabets #20`.

## Releasing

Maintainers only:

1. Bump the version in the two `COMMENT ON FUNCTION` lines at the end of `nanoid.sql`.
2. Merge to `main` and wait for the test workflow to pass.
3. Publish a GitHub release with the tag `X.Y.Z` (no `v` prefix), the title `vX.Y.Z - <summary>`, and notes in the shape
   of the previous releases.
