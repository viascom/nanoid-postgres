# Nano ID for PostgreSQL

_Inspired by the following parent project: [ai/nanoid](https://github.com/ai/nanoid)_

<img src="./logo.svg" align="right" alt="Nano ID logo by Anton Lovchikov" width="180" height="94">

A tiny, secure, URL-friendly, unique string ID generator for Postgres.

> “An amazing level of senseless perfectionism, which is simply impossible not to respect.”

* **Small.** Just a simple Postgres function.
* **Safe.** It uses pgcrypto random generator. Can be used in clusters.
* **Short IDs.** It uses a larger alphabet than UUID (`A-Za-z0-9_-`). So ID size was reduced from 36 to 21 symbols.
* **Portable**. Nano ID was ported
  to [over 20 programming languages](https://github.com/ai/nanoid/blob/main/README.md#other-programming-languages).

## How to use

```sql
SELECT nanoid(); -- Simplest way to use this function. Creates an id, with the defaults of the created nanoid() function.
SELECT nanoid(4); -- size parameter set to return 4 digit ids only
SELECT nanoid(3, 'abcdefghij'); -- custom size and alphabet parameters defined. nanoid() generates ids concerning them.
SELECT nanoid(10, '23456789abcdefghijklmnopqrstuvwxyz', 1.85); -- nanoid() could generates ids more performant with a custom defined additional bytes factor.
```

```sql
CREATE TABLE mytable(
    id char(21) DEFAULT nanoid() PRIMARY KEY
);

or

-- To use a custom id size
CREATE TABLE mytable(
    id char(14) DEFAULT nanoid(14) PRIMARY KEY
);

or

-- To use a custom id size and a custom alphabet
CREATE TABLE mytable(
    id char(12) DEFAULT nanoid(12, 'ABC123') PRIMARY KEY
);
```

### Using nanoid() with an existing table

To make `nanoid()` the default of an already existing column, change the column default:

```sql
ALTER TABLE mytable ALTER COLUMN id SET DEFAULT nanoid();
```

This only affects future inserts. Existing rows keep their current values, and rows inserted without a value for `id`
get a freshly generated Nano ID. See the PostgreSQL documentation on
[changing a column's default value](https://www.postgresql.org/docs/current/ddl-alter.html#DDL-ALTER-COLUMN-DEFAULT)
for details.

## Getting Started

### Requirements

* PostgreSQL 9.6 or newer (the function declarations use the `PARALLEL` clause, which was introduced in 9.6)

Execute the file `nanoid.sql` to create the `nanoid()` function on your defined schema. The nanoid() function will only
be available in the specific database where you run the SQL code provided.

**Manually create the function in each database:** You can connect to each database and create the function. This
function can be created manually or through a script if you have many databases. Remember to manage updates to the
function. If you change the function in one database, those changes will only be reflected in the other databases if you
update each function.

## Adding to the default template database

**Use a template database:** If you often create databases that need to have the same set of functions, you could create
a template database that includes these functions. Then, when you create a new database, you can specify this template,
and PostgreSQL will make the new database a copy of the template.

Here's how to do that:

1. Connect to template1 database:
2. Then, run your `nanoid()` function creation code.

*If the function is only needed for specific applications, it might be better to create it manually in each database
where needed or create a custom template database that includes this function and use that template when creating new
databases for these applications.*

Also, note that changes to template1 won't affect existing databases, only new ones created after the changes. Existing
databases will need to have the function added manually if required.

Reference: [Template Databases](https://www.postgresql.org/docs/current/manage-ag-templatedbs.html)

## The additional bytes factor

`nanoid()` batches its random bytes: the step size `min(1024, ceil(additionalBytesFactor * 256 * size / cutoff))`
already accounts for the expected share of rejected bytes of your alphabet, so the default factor of `1.6` works well for
every alphabet (it is the same safety margin the original JavaScript library uses). A higher factor lowers the chance
that a second `gen_random_bytes()` batch is needed at the cost of more memory per call; a factor closer to `1.0`
conserves memory but requests follow-up batches more often. The step is capped at 1024 because `gen_random_bytes()`
accepts at most 1024 bytes per call, so once that cap is reached a higher factor can no longer reduce the number of
follow-up batches.

```sql
-- Example: trade a little memory for fewer follow-up batches
SELECT nanoid(10, '23456789abcdefghijklmnopqrstuvwxyz', 2.0);
```

## Usage Guide: `nanoid_optimized()`

The `nanoid_optimized()` function is an advanced version of the `nanoid()` function designed for higher performance and
lower memory overhead. While it provides a more efficient mechanism to generate unique identifiers, it assumes that you
know precisely how you want to use it.

🚫 **Warning**: No checks are performed inside `nanoid_optimized()`. Use it only if you're sure about the parameters you'
re passing.

### Function Signature

```sql
nanoid_optimized(
    size int,
    alphabet text,
    cutoff int,
    step int
) RETURNS text;
```

### Parameters

- `size`: The desired length of the generated string.
- `alphabet`: The set of characters to choose from for generating the string.
- `cutoff`: The exclusive upper bound for accepted random bytes. The value should be `256 - (256 % length(alphabet))`;
  bytes greater than or equal to it are rejected to avoid modulo bias.
- `step`: The number of random bytes to generate in each iteration. A larger value might speed up the function but will
  also increase memory usage.

### Example Usage

Generate a NanoId String of length 10 using the default alphabet set:

```sql
SELECT nanoid_optimized(10, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 256, 16);
```

### Tips:

- **Performance**: This function is optimized for performance, so it's ideal for scenarios where high-speed ID
  generation is needed.
- **Alphabet Set**: The larger your alphabet set, the more unique your generated IDs will be, but also consider the
  cutoff and step parameters' adjustments.
- **Customization**: Feel free to adjust the parameters to suit your specific needs, but always be cautious about the
  values you're inputting.

By following this guide, you can seamlessly integrate the `nanoid_optimized()` function into your projects and enjoy the
benefits of its optimized performance.

### LEAKPROOF Setting

#### Default Configuration

The `nanoid()` function is configured without the `LEAKPROOF` attribute by default to ensure compatibility across
diverse environments, including cloud platforms and managed services, without the need for superuser privileges.

#### When to Enable LEAKPROOF

Enabling `LEAKPROOF` is optional and beneficial in environments that require enhanced security measures, such as those
utilizing row-level security (RLS). This setting should be considered if you have superuser access and seek to further
restrict information leakage.

**Note:** To apply the LEAKPROOF attribute, uncomment the LEAKPROOF line in the function definition. This setting
is permissible only for superusers due to its implications for database security and operation.

## 🧪 Running the tests

The repository ships a test suite that installs `nanoid.sql` into the official PostgreSQL Docker images (latest minor
of every major version from 9.6 through 18) and runs the unit tests plus regression tests against each of them. The
regression tests cover the parallel-query scenarios from
[issue #16](https://github.com/viascom/nanoid-postgres/issues/16) and large-size id generation.

Requirements: Docker.

```bash
# Test all supported versions (9.6 through 18)
dev/test/run_tests.sh

# Test only specific versions
dev/test/run_tests.sh 16 17 18
```

The script prints a per-version PASS/FAIL summary and exits non-zero if any version fails.

## Using MySQL/MariaDB?

If you're using MySQL or MariaDB and you found this library helpful, we have a similar library for MySQL/MariaDB, too!
Check out our [Nano ID for MySQL/MariaDB](https://github.com/viascom/nanoid-mysql-mariadb) repository to use the same
capabilities in your MySQL/MariaDB databases.

## 🌱 Contributors Welcome

- 🐛 **Encountered a Bug?** Let us know with an issue. Every bit of feedback helps enhance the project.

- 💡 **Interested in Contributing Code?** Simply fork and submit a pull request. Every contribution, no matter its size,
  is valued.

- 📣 **Have Some Ideas?** We're always open to suggestions. Initiate an issue for discussions or to share your insights.

All relevant details about the project can be found in this README.

Your active participation 🤝 is a cornerstone of **nanoid-postgres**. Thank you for joining us on this journey.

## 🖥️ Authors

* **Patrick Bösch** - *Initial work* - [itsmefox](https://github.com/itsmefox)
* **Nikola Stanković** - *Initial work* - [nik-sta](https://github.com/nik-sta)

See also the list of [contributors](https://github.com/viascom/nanoid-postgres/contributors) who participated in this
project. 💕

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
