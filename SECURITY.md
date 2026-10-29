# Security

Only the newest release is supported. Report a vulnerability privately through
[GitHub's security advisories](https://github.com/viascom/nanoid-postgres/security/advisories/new),
not in a public issue.

The functions read no tables and write no data. They build ids from the parameters you pass and from
`gen_random_bytes()` of the pgcrypto extension, which draws on the server's cryptographically strong random source.
They are `SECURITY INVOKER` functions, so they run with the privileges of the role that calls them.
