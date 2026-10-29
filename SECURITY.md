# Security policy

## Supported versions

Security fixes go into the latest release. Upgrading is a matter of running the new `nanoid.sql`; see
[Upgrading](README.md#upgrading). To check which version a database runs:

```sql
SELECT obj_description('nanoid'::regproc, 'pg_proc'); -- e.g. nanoid-postgres 3.1.0
```

## Reporting a vulnerability

Please do not open a public issue. Report the vulnerability privately through
[GitHub private vulnerability reporting](https://github.com/viascom/nanoid-postgres/security/advisories/new).

Include the nanoid-postgres version, the PostgreSQL version (`SELECT version();`) and the SQL that reproduces the
problem. The maintainers reply in the private advisory, and publish the advisory together with a fixed release.

Examples of what to report:

- generated ids that are biased, predictable or repeat more often than their size and alphabet allow
- input that makes a function hang, or exhaust memory or CPU beyond what the requested size needs
- anything in `nanoid.sql` that reads or changes data or privileges beyond creating its own functions and the pgcrypto
  extension

The functions read no tables and write no data. They build ids from the parameters you pass and from
`gen_random_bytes()` of the pgcrypto extension, which draws on the server's cryptographically strong random source,
and they run with the privileges of the calling role (`SECURITY INVOKER`).
