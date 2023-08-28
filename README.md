# Nano ID for PostgreSQL

_Inspired by the following parent project: [ai/nanoid](https://github.com/ai/nanoid)_

<img src="./logo.svg" align="right" alt="Nano ID logo by Anton Lovchikov" width="180" height="94">

A tiny, secure, URL-friendly, unique string ID generator for Postgres.

> “An amazing level of senseless perfectionism, which is simply impossible not to respect.”

* **Small.** Just a simple Postgres function.
* **Safe.** It uses pgcrypto random generator. Can be used in clusters.
* **Short IDs.** It uses a larger alphabet than UUID (`A-Za-z0-9_-`). So ID size was reduced from 36 to 21 symbols.
* **Portable**. Nano ID was ported to [over 20 programming languages](https://github.com/ai/nanoid/blob/main/README.md#other-programming-languages).

## Use
```sql
SELECT nanoid(); -- creates an id, with the defaults of the created nanoid() function.
SELECT nanoid(4); -- size parameter set to return 4 digit ids only
SELECT nanoid(3, 'abcdefghij'); -- custom size and alphabet parameters defined. nanoid() generates ids concerning them
```

```sql
CREATE TABLE mytable (
  id char(21) DEFAULT nanoid() PRIMARY KEY
);

or

-- To use a custom id size
CREATE TABLE mytable (
  id char(14) DEFAULT nanoid(14) PRIMARY KEY
);

or

-- To use a custom id size and a custom alphabet
CREATE TABLE mytable (
  id char(12) DEFAULT nanoid(12, 'ABC123') PRIMARY KEY
);
```

## Getting Started

### Requirements
* PostgreSQL 9.4 or newer

Execute the file `nanoid.sql` to create the `nanoid()` function on your defined schema. The nanoid() function will only be available in the specific database where you run the SQL code provided.

**Manually create the function in each database:** You can connect to each database and create the function. This function can be created manually or through a script if you have many databases. Remember to manage updates to the function. If you change the function in one database, those changes will only be reflected in the other databases if you update each function.

### Adding to the default template database

**Use a template database:** If you often create databases that need to have the same set of functions, you could create a template database that includes these functions. Then, when you create a new database, you can specify this template, and PostgreSQL will make the new database a copy of the template.

Here's how to do that:
1. Connect to template1 database:
2. Then, run your nanoid() function creation code.

*If the function is only needed for specific applications, it might be better to create it manually in each database where needed or create a custom template database that includes this function and use that template when creating new databases for these applications.*

Also, note that changes to template1 won't affect existing databases, only new ones created after the changes. Existing databases will need to have the function added manually if required.

Reference: [Template Databases](https://www.postgresql.org/docs/current/manage-ag-templatedbs.html)

## Using MySQL/MariaDB?

If you're using MySQL or MariaDB and you found this library helpful, we have a similar library for MySQL/MariaDB, too! Check out our [Nano ID for MySQL/MariaDB](https://github.com/viascom/nanoid-mysql-mariadb) repository to use the same capabilities in your MySQL/MariaDB databases.

## Authors 🖥️

* **Patrick Bösch** - *Initial work* - [itsmefox](https://github.com/itsmefox)
* **Nikola Stanković** - *Initial work* - [nik-sta](https://github.com/nik-sta)

See also the list of [contributors](https://github.com/viascom/nanoid-postgres/contributors) who participated in this project. 💕

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
