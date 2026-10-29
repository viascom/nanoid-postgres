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

-- Returns the message of the exception the statement raises, or NULL if it raises none.
CREATE FUNCTION pg_temp.raised_message(statement text) RETURNS text
    LANGUAGE plpgsql AS
$$
BEGIN
    EXECUTE statement;
    RETURN NULL;
EXCEPTION
    WHEN raise_exception THEN RETURN SQLERRM;
END
$$;

-- Upstream ai/nanoid's flatness check: the per-symbol frequency, normalized to 1.0 for a perfectly
-- even split, must not spread by more than 0.05 between the most and least frequent symbol.
CREATE FUNCTION pg_temp.symbol_spread(alphabet text, size int, ids int, OUT symbols bigint, OUT spread float)
    LANGUAGE sql AS
$$
SELECT count(*), (max(n) - min(n)) * length(alphabet)::float / (ids * size)
FROM (SELECT count(*) n
      FROM (SELECT regexp_split_to_table(nanoid(size, alphabet), '') ch FROM generate_series(1, ids)) s
      GROUP BY ch) c
$$;

DO
$$
    DECLARE
        generated_id     text;
        counter          int;
        numLoops         int := 1000;
        alphabet256      text;
        alphabet64       text;
        alphabet         text;
        defaultAlphabet  text;
        functionSource   text;
        statement        text;
        symbols          bigint;
        spread           float;
    BEGIN
        -- Default parameters
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid();
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 21, 'Default nanoid length is incorrect';
                ASSERT generated_id ~ '^[-_a-zA-Z0-9]*$', 'Default nanoid contains invalid characters';
            END LOOP;

        -- Size 12, default alphabet
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(12);
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 12, 'Size 12 nanoid length is incorrect';
                ASSERT generated_id ~ '^[-_a-zA-Z0-9]*$', 'Size 12 nanoid contains invalid characters';
            END LOOP;

        -- Size 25, default alphabet
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(25);
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 25, 'Size 25 nanoid length is incorrect';
                ASSERT generated_id ~ '^[-_a-zA-Z0-9]*$', 'Size 25 nanoid contains invalid characters';
            END LOOP;

        -- Default size (21), custom alphabet (only lowercase)
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(21, 'abcdefghijklmnopqrstuvwxyz');
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 21, 'Size 21 (only lowercase) nanoid length is incorrect';
                ASSERT generated_id ~ '^[a-z]*$', 'Size 21 (only lowercase) nanoid contains invalid characters';
            END LOOP;

        -- Size 15, custom alphabet (only numbers)
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(15, '0123456789');
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 15, 'Size 15 (only numbers) nanoid length is incorrect';
                ASSERT generated_id ~ '^[0-9]*$', 'Size 15 (only numbers) nanoid contains invalid characters';
            END LOOP;

        -- Size 17, custom alphabet (uppercase + numbers)
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(17, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 17, 'Size 17 (uppercase + numbers) nanoid length is incorrect';
                ASSERT generated_id ~ '^[A-Z0-9]*$', 'Size 17 (uppercase + numbers) nanoid contains invalid characters';
            END LOOP;

        -- Size 5, single-symbol alphabet
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(5, 'a');
                RAISE NOTICE '%', generated_id;
                ASSERT generated_id = 'aaaaa', 'Size 5 (single-symbol alphabet) nanoid is incorrect';
            END LOOP;

        -- Non-power-of-two alphabet (33 symbols): every symbol must be reachable
        generated_id := nanoid(5000, 'abcdefghijklmnopqrstuvwxyz0123456');
        ASSERT LENGTH(generated_id) = 5000, 'Size 5000 (33 symbols) nanoid length is incorrect';
        ASSERT generated_id ~ '^[a-z0-6]*$', 'Size 5000 (33 symbols) nanoid contains invalid characters';
        FOR counter IN 1..33
            LOOP
                ASSERT position(substr('abcdefghijklmnopqrstuvwxyz0123456', counter, 1) in generated_id) > 0,
                    'Symbol missing in output of 33-symbol alphabet';
            END LOOP;

        -- Size 21, maximum-length alphabet (256 unique symbols)
        -- Requires a UTF8-encoded database: chr() rejects code points above 255 under
        -- single-byte encodings. The official PostgreSQL Docker images default to UTF8.
        alphabet256 := (SELECT string_agg(chr(i), '' ORDER BY i) FROM generate_series(192, 447) AS i);
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(21, alphabet256);
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 21, 'Size 21 (256-symbol alphabet) nanoid length is incorrect';
                ASSERT translate(generated_id, alphabet256, '') = '',
                    'Size 21 (256-symbol alphabet) nanoid contains characters outside the alphabet';
            END LOOP;

        -- Alphabets with more than 256 symbols are rejected
        ASSERT pg_temp.raised_message(format('SELECT nanoid(21, %L)', alphabet256 || chr(448))) LIKE '%bigger than 256 symbols%',
            'Alphabet with more than 256 symbols was not rejected';

        -- Default size (21) with a prefix: the prefix does not count towards the size
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, 'usr_');
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 25, 'Prefixed nanoid length is incorrect';
                ASSERT generated_id ~ '^usr_[-_a-zA-Z0-9]{21}$', 'Prefixed nanoid has a wrong prefix or invalid characters';
            END LOOP;

        -- Prefix via named notation, all other parameters use their defaults
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(prefix => 'ord_');
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 25, 'Named-notation prefixed nanoid length is incorrect';
                ASSERT generated_id ~ '^ord_[-_a-zA-Z0-9]{21}$', 'Named-notation prefixed nanoid has a wrong prefix or invalid characters';
            END LOOP;

        -- NULL prefix behaves like no prefix instead of producing a NULL id
        generated_id := nanoid(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, NULL);
        ASSERT generated_id IS NOT NULL, 'NULL prefix must not produce a NULL id';
        ASSERT LENGTH(generated_id) = 21, 'NULL prefix nanoid length is incorrect';
        ASSERT generated_id ~ '^[-_a-zA-Z0-9]*$', 'NULL prefix nanoid contains invalid characters';

        -- The prefix is not validated against the alphabet: characters outside the alphabet
        -- (including multi-byte ones) pass through unchanged
        generated_id := nanoid(5, 'abc', 1.6, 'usr#ü_');
        ASSERT LENGTH(generated_id) = 11, 'Out-of-alphabet prefix nanoid length is incorrect';
        ASSERT generated_id ~ '^usr#ü_[abc]{5}$', 'Out-of-alphabet prefix was altered or random part is invalid';

        -- Mixed notation: positional size with a named prefix
        generated_id := nanoid(12, prefix => 'x');
        ASSERT LENGTH(generated_id) = 13, 'Mixed-notation prefixed nanoid length is incorrect';
        ASSERT generated_id ~ '^x[-_a-zA-Z0-9]{12}$', 'Mixed-notation prefixed nanoid has a wrong prefix or invalid characters';

        -- 64-symbol alphabets go through base64 encoding: sizes past the 76-character line wrap
        -- of encode() and across the 1365/1366 switch to the byte loop keep length and charset
        FOR counter IN 1..1400
            LOOP
                generated_id := nanoid(counter);
                ASSERT LENGTH(generated_id) = counter, 'Size ' || counter || ' nanoid length is incorrect';
                ASSERT generated_id ~ '^[-_a-zA-Z0-9]*$', 'Size ' || counter || ' nanoid contains invalid characters';
            END LOOP;

        -- The last symbol must carry 6 full random bits for every size modulo 4: a short byte
        -- count would limit it to a subset of the alphabet
        FOR counter IN 1..4
            LOOP
                ASSERT (SELECT count(DISTINCT right(nanoid(counter), 1)) FROM generate_series(1, 5000)) = 64,
                    'Last symbol of size ' || counter || ' nanoid does not cover all 64 symbols';
            END LOOP;

        -- Every symbol of the default alphabet is reachable
        generated_id := nanoid(1365);
        FOR counter IN 1..64
            LOOP
                ASSERT position(substr('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_', counter, 1) in generated_id) > 0,
                    'Symbol missing in output of the default alphabet';
            END LOOP;

        -- Custom 64-symbol alphabet with multi-byte symbols: every symbol is reachable and no
        -- base64 symbol leaks through
        alphabet64 := 'абвгдежзийклмнопрстуфхцчшщъыьэюяАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ';
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid(21, alphabet64);
                ASSERT LENGTH(generated_id) = 21, 'Size 21 (64 multi-byte symbols) nanoid length is incorrect';
                ASSERT translate(generated_id, alphabet64, '') = '',
                    'Size 21 (64 multi-byte symbols) nanoid contains characters outside the alphabet';
            END LOOP;
        generated_id := nanoid(1365, alphabet64);
        FOR counter IN 1..64
            LOOP
                ASSERT position(substr(alphabet64, counter, 1) in generated_id) > 0,
                    'Symbol missing in output of a custom 64-symbol alphabet';
            END LOOP;

        -- The fast-path comparison in nanoid() must use the declared default alphabet, or the
        -- default call silently loses its cheap two-symbol translate()
        SELECT substring(pg_get_expr(proargdefaults, 0) FROM '''([^'']+)'''), prosrc
        INTO defaultAlphabet, functionSource
        FROM pg_proc
        WHERE proname = 'nanoid';
        ASSERT defaultAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_',
            'Unexpected default alphabet: ' || coalesce(defaultAlphabet, 'NULL');
        ASSERT position('''' || defaultAlphabet || ''' COLLATE "C"' in functionSource) > 0,
            'The fast-path comparison in nanoid() does not match the default alphabet';

        -- Flat distribution (upstream criterion) on each generation path: base64 with the default
        -- alphabet, base64 with a full translate(), and the byte loop with cutoff rejection
        SELECT * INTO symbols, spread FROM pg_temp.symbol_spread(defaultAlphabet, 21, 200000);
        ASSERT symbols = 64 AND spread <= 0.05, 'Default alphabet distribution is not flat: ' || spread;
        SELECT * INTO symbols, spread FROM pg_temp.symbol_spread(alphabet64, 21, 200000);
        ASSERT symbols = 64 AND spread <= 0.05, 'Custom 64-symbol distribution is not flat: ' || spread;
        SELECT * INTO symbols, spread FROM pg_temp.symbol_spread('abcdefghijklmnopqrstuvwxyz', 30, 50000);
        ASSERT symbols = 26 AND spread <= 0.05, '26-symbol distribution is not flat: ' || spread;

        -- Alphabet lengths around the base64 path, power-of-two alphabets on the byte loop, and
        -- 4-byte UTF-8 symbols (emoji) on both paths: correct length, only alphabet symbols, every
        -- symbol reachable. Size 1365 is the largest that still takes the base64 path.
        FOREACH alphabet IN ARRAY ARRAY [
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.',
            '0123456789abcdef',
            '01',
            (SELECT string_agg(chr(i), '' ORDER BY i) FROM generate_series(128512, 128575) AS i),
            (SELECT string_agg(chr(i), '' ORDER BY i) FROM generate_series(128512, 128516) AS i)]
            LOOP
                ASSERT length(nanoid(1, alphabet)) = 1, length(alphabet) || '-symbol nanoid(1) length is incorrect';
                generated_id := nanoid(1365, alphabet);
                ASSERT length(generated_id) = 1365, length(alphabet) || '-symbol nanoid length is incorrect';
                ASSERT translate(generated_id, alphabet, '') = '',
                    length(alphabet) || '-symbol nanoid contains characters outside the alphabet';
                FOR counter IN 1..length(alphabet)
                    LOOP
                        ASSERT position(substr(alphabet, counter, 1) in generated_id) > 0,
                            'Symbol missing in output of ' || length(alphabet) || '-symbol alphabet';
                    END LOOP;
            END LOOP;

        -- Duplicate symbols are allowed and only make those symbols more likely
        ASSERT nanoid(50, repeat('ab', 32)) ~ '^[ab]{50}$', 'Duplicate symbols in a 64-symbol alphabet failed';
        ASSERT nanoid(50, 'aab') ~ '^[ab]{50}$', 'Duplicate symbols in a 3-symbol alphabet failed';

        -- The additional bytes factor accepts its minimum and values far above the 1024-byte step cap
        ASSERT nanoid(30, '0123456789', 1) ~ '^[0-9]{30}$', 'Additional bytes factor 1 failed';
        ASSERT nanoid(30, '0123456789', 1000) ~ '^[0-9]{30}$', 'Additional bytes factor 1000 failed';

        -- nanoid_optimized() with a non-power-of-two alphabet and a matching cutoff
        ASSERT nanoid_optimized(30, '0123456789', 250, 20) ~ '^[0-9]{30}$', 'nanoid_optimized() with 10 symbols failed';

        -- Invalid input raises instead of returning a wrong id or looping forever
        ASSERT pg_temp.raised_message('SELECT nanoid(NULL)') LIKE '%size must be defined%', 'nanoid(NULL) was not rejected';
        ASSERT pg_temp.raised_message('SELECT nanoid(0)') LIKE '%size must be defined%', 'nanoid(0) was not rejected';
        ASSERT pg_temp.raised_message('SELECT nanoid(-10)') LIKE '%size must be defined%', 'nanoid(-10) was not rejected';
        ASSERT pg_temp.raised_message('SELECT nanoid(21, NULL)') LIKE '%alphabet can''t be undefined%', 'NULL alphabet was not rejected';
        ASSERT pg_temp.raised_message('SELECT nanoid(21, '''')') LIKE '%alphabet can''t be undefined%', 'Empty alphabet was not rejected';
        ASSERT pg_temp.raised_message('SELECT nanoid(21, ''abc'', NULL)') LIKE '%factor can''t be less than 1%', 'NULL additional bytes factor was not rejected';
        ASSERT pg_temp.raised_message('SELECT nanoid(21, ''abc'', 0.99)') LIKE '%factor can''t be less than 1%', 'Additional bytes factor below 1 was not rejected';

        -- nanoid_optimized() termination guards (issue #32)
        FOREACH statement IN ARRAY ARRAY [
            'SELECT nanoid_optimized(NULL, ''abc'', 255, 10)',
            'SELECT nanoid_optimized(-1, ''abc'', 255, 10)',
            'SELECT nanoid_optimized(10, NULL, 255, 10)',
            'SELECT nanoid_optimized(10, '''', 255, 10)',
            'SELECT nanoid_optimized(10, ''abc'', NULL, 10)',
            'SELECT nanoid_optimized(10, ''abc'', 0, 10)',
            'SELECT nanoid_optimized(10, ''abc'', 255, NULL)',
            'SELECT nanoid_optimized(10, ''abc'', 255, 0)']
            LOOP
                ASSERT pg_temp.raised_message(statement) IS NOT NULL, 'Not rejected: ' || statement;
            END LOOP;

        --         -- Intentional false positive: use default size but with a mismatched regex pattern
--         FOR counter IN 1..numLoops
--             LOOP
--                 generated_id := nanoid();
--                 RAISE NOTICE '%', generated_id;
--                 -- This will fail because we're purposefully using a wrong pattern
--                 ASSERT generated_id ~ '^[XYZ]*$', 'Intentional false positive detected';
--             END LOOP;

        RAISE NOTICE 'All tests passed successfully!';
    END
$$;