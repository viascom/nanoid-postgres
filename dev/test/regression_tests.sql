/*
 * Copyright 2026 Viascom Ltd liab. Co
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

-- Regression tests for nanoid.sql. Run after installing nanoid.sql, e.g. via dev/test/run_tests.sh.
-- Compatible with PostgreSQL 9.6 through 18. Every statement must succeed; failures abort the run
-- when executed with ON_ERROR_STOP=1.

-- ---------------------------------------------------------------------------------------------
-- Issue #16: nanoid() and nanoid_optimized() must not raise
-- "cannot start commands during a parallel operation".
-- PL/pgSQL advances the command counter and takes new snapshots when evaluating volatile
-- expressions, which is forbidden in parallel mode. Both functions are therefore declared
-- PARALLEL UNSAFE. These tests make parallel plans as attractive as possible and then run the
-- query shapes that failed with the earlier PARALLEL SAFE / PARALLEL RESTRICTED declarations.
-- ---------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS nanoid_test_src;
CREATE TABLE nanoid_test_src AS
SELECT g
FROM generate_series(1, 50000) g;
ANALYZE nanoid_test_src;

-- Make parallel plans maximally attractive. Guard the settings whose names changed between
-- versions (9.6 uses min_parallel_relation_size, 10+ uses min_parallel_table_scan_size).
DO
$$
BEGIN
    PERFORM set_config('max_parallel_workers_per_gather', '4', false);
    PERFORM set_config('parallel_setup_cost', '0', false);
    PERFORM set_config('parallel_tuple_cost', '0', false);
    IF EXISTS (SELECT 1 FROM pg_settings WHERE name = 'min_parallel_table_scan_size') THEN
        PERFORM set_config('min_parallel_table_scan_size', '0', false);
    END IF;
    IF EXISTS (SELECT 1 FROM pg_settings WHERE name = 'min_parallel_relation_size') THEN
        PERFORM set_config('min_parallel_relation_size', '0', false);
    END IF;
END
$$;

-- Plain SELECT over a parallel-eligible scan.
SELECT count(x) AS plain_select_ok
FROM (SELECT nanoid() AS x FROM nanoid_test_src) q;

-- CREATE TABLE AS uses parallel plans on PostgreSQL 11+ and is the vanilla-PostgreSQL
-- reproduction of issue #16 (it failed with both PARALLEL SAFE and PARALLEL RESTRICTED).
DROP TABLE IF EXISTS nanoid_test_ctas;
CREATE TABLE nanoid_test_ctas AS
SELECT nanoid() AS id
FROM nanoid_test_src;

-- Same reproduction for direct nanoid_optimized() usage, which is a documented public API.
DROP TABLE IF EXISTS nanoid_test_ctas_optimized;
CREATE TABLE nanoid_test_ctas_optimized AS
SELECT nanoid_optimized(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 256, 34) AS id
FROM nanoid_test_src;

-- The exact query shape from issue #16 (backfilling a mapping table).
DROP TABLE IF EXISTS nanoid_test_map;
CREATE TABLE nanoid_test_map
(
    old int,
    new text
);
INSERT INTO nanoid_test_map(old, new)
SELECT g, nanoid()
FROM nanoid_test_src;

-- Verify the generated data: correct row counts, correct length, no collisions.
DO
$$
DECLARE
    total    bigint;
    distinct_ids bigint;
BEGIN
    SELECT count(*), count(DISTINCT id) INTO total, distinct_ids FROM nanoid_test_ctas;
    ASSERT total = 50000, 'CTAS produced wrong row count: ' || total;
    ASSERT distinct_ids = 50000, 'CTAS produced duplicate ids';

    SELECT count(*), count(DISTINCT id) INTO total, distinct_ids FROM nanoid_test_ctas_optimized;
    ASSERT total = 50000, 'CTAS over nanoid_optimized produced wrong row count: ' || total;
    ASSERT distinct_ids = 50000, 'CTAS over nanoid_optimized produced duplicate ids';

    SELECT count(*), count(DISTINCT new) INTO total, distinct_ids FROM nanoid_test_map;
    ASSERT total = 50000, 'INSERT ... SELECT produced wrong row count: ' || total;
    ASSERT distinct_ids = 50000, 'INSERT ... SELECT produced duplicate ids';

    SELECT count(*) INTO total FROM nanoid_test_map WHERE length(new) <> 21;
    ASSERT total = 0, 'INSERT ... SELECT produced ids with wrong length';
END
$$;

-- ---------------------------------------------------------------------------------------------
-- Issue #32: nanoid_optimized() must reject inputs that would otherwise spin its generation
-- loop forever (the only exit is reached after a character has been appended).
-- ---------------------------------------------------------------------------------------------
DO
$$
    DECLARE
        guard_fired boolean := false;
    BEGIN
        BEGIN
            PERFORM nanoid_optimized(0, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 256, 34);
        EXCEPTION
            WHEN raise_exception THEN guard_fired := true;
        END;
        ASSERT guard_fired, 'nanoid_optimized() termination guard did not fire';
    END
$$;

-- ---------------------------------------------------------------------------------------------
-- No artificial size cap: id generation must work for any requested length, including sizes
-- that need more than 100 passes over the byte-generation loop (step is capped at 1024, so
-- 102401 characters with the default alphabet need 101 passes).
-- ---------------------------------------------------------------------------------------------
DO
$$
BEGIN
    ASSERT length(nanoid(102401)) = 102401, 'large nanoid() failed';
    ASSERT length(nanoid_optimized(300, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 256, 2)) = 300,
        'nanoid_optimized() with a small step failed';
END
$$;

-- ---------------------------------------------------------------------------------------------
-- Issue #38: the functions must not depend on the caller's search_path. A caller that only has
-- pg_catalog on its path reaches them with a qualified call; gen_random_bytes() and
-- nanoid_optimized() must still resolve inside. run_tests.sh covers pgcrypto in its own schema.
-- ---------------------------------------------------------------------------------------------
DO
$$
    DECLARE
        nanoidSchema text := (SELECT pronamespace::regnamespace::text
                              FROM pg_proc
                              WHERE oid = 'nanoid(int, text, float, text)'::regprocedure);
        generatedId  text;
    BEGIN
        PERFORM set_config('search_path', 'pg_catalog', true);
        EXECUTE format('SELECT %s.nanoid()', nanoidSchema) INTO generatedId;
        ASSERT length(generatedId) = 21, 'Qualified nanoid() failed without its schema on the search_path';
        EXECUTE format('SELECT %s.nanoid(10, ''abc'')', nanoidSchema) INTO generatedId;
        ASSERT generatedId ~ '^[abc]{10}$', 'Qualified nanoid() with a custom alphabet failed without its schema on the search_path';
    END
$$;

-- ---------------------------------------------------------------------------------------------
-- Issue #39: edge cases aligned with nanoid-mysql-mariadb and nanoid-kotlin. A non-finite
-- additional bytes factor is rejected, and nanoid_optimized() rejects a cutoff whose accepted
-- byte values do not split evenly over the alphabet (biased ids or unreachable symbols).
-- ---------------------------------------------------------------------------------------------
DO
$$
    DECLARE
        statement   text;
        message     text;
        generatedId text;
    BEGIN
        FOREACH statement IN ARRAY ARRAY [
            'SELECT nanoid(10, ''abc'', ''Infinity'')',
            'SELECT nanoid(10, ''abc'', ''NaN'')',
            'SELECT nanoid_optimized(10, ''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'', 63, 16)',
            'SELECT nanoid_optimized(10, ''abc'', 2, 16)',
            'SELECT nanoid_optimized(10, ''abc'', 256, 16)']
            LOOP
                message := NULL;
                BEGIN
                    EXECUTE statement;
                EXCEPTION
                    WHEN raise_exception THEN message := SQLERRM;
                END;
                ASSERT message IS NOT NULL, 'Not rejected: ' || statement;
            END LOOP;

        -- Cutoffs that split evenly keep working, including values above 256 for alphabets
        -- whose length divides 256 (every byte is accepted there)
        ASSERT nanoid_optimized(10, 'abc', 255, 16) ~ '^[abc]{10}$', 'Cutoff 255 with 3 symbols failed';
        ASSERT nanoid_optimized(10, 'abc', 129, 16) ~ '^[abc]{10}$', 'Cutoff 129 with 3 symbols failed';
        ASSERT nanoid_optimized(10, '0123456789abcdef', 300, 16) ~ '^[0-9a-f]{10}$', 'Cutoff 300 with 16 symbols failed';

        -- Alphabets whose length divides 256 request exactly size bytes: sizes on both sides of
        -- the 1024-byte cap still come out complete
        generatedId := nanoid(1024, '0123456789abcdef');
        ASSERT length(generatedId) = 1024 AND generatedId ~ '^[0-9a-f]+$', 'Size 1024 with 16 symbols failed';
        generatedId := nanoid(3000, '01');
        ASSERT length(generatedId) = 3000 AND generatedId ~ '^[01]+$', 'Size 3000 with 2 symbols failed';
    END
$$;

-- Cleanup.
DROP TABLE IF EXISTS nanoid_test_src;
DROP TABLE IF EXISTS nanoid_test_ctas;
DROP TABLE IF EXISTS nanoid_test_ctas_optimized;
DROP TABLE IF EXISTS nanoid_test_map;
