/*
 * Copyright 2026 Viascom Ltd liab. Co
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
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
-- nanoid_non_secure() is PL/pgSQL with volatile expressions too, so the issue #16 constraint
-- applies to it as well: it must be declared PARALLEL UNSAFE to keep parallel plans away.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS nanoid_test_ctas_non_secure;
CREATE TABLE nanoid_test_ctas_non_secure AS
SELECT nanoid_non_secure() AS id
FROM nanoid_test_src;

DO
$$
DECLARE
    total bigint;
BEGIN
    SELECT count(*) INTO total FROM nanoid_test_ctas_non_secure;
    ASSERT total = 50000, 'CTAS over nanoid_non_secure produced wrong row count: ' || total;

    SELECT count(*) INTO total FROM nanoid_test_ctas_non_secure WHERE length(id) <> 21;
    ASSERT total = 0, 'CTAS over nanoid_non_secure produced ids with wrong length';
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

-- Cleanup.
DROP TABLE IF EXISTS nanoid_test_src;
DROP TABLE IF EXISTS nanoid_test_ctas;
DROP TABLE IF EXISTS nanoid_test_ctas_optimized;
DROP TABLE IF EXISTS nanoid_test_ctas_non_secure;
DROP TABLE IF EXISTS nanoid_test_map;
