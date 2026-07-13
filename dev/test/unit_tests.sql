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

DO
$$
    DECLARE
        generated_id  text;
        counter       int;
        numLoops      int := 1000;
        alphabet256   text;
        error_message text;
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
        BEGIN
            generated_id := nanoid(21, alphabet256 || chr(448));
            ASSERT FALSE, 'Alphabet with more than 256 symbols was not rejected';
        EXCEPTION
            WHEN assert_failure THEN RAISE;
            WHEN raise_exception THEN
                GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
                ASSERT error_message LIKE '%bigger than 256 symbols%',
                    'Alphabet rejection raised an unexpected error: ' || error_message;
        END;

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

        -- Non-secure variant: default parameters
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid_non_secure();
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 21, 'Default nanoid_non_secure length is incorrect';
                ASSERT generated_id ~ '^[-_a-zA-Z0-9]*$', 'Default nanoid_non_secure contains invalid characters';
            END LOOP;

        -- Non-secure variant: custom size and alphabet (only numbers)
        FOR counter IN 1..numLoops
            LOOP
                generated_id := nanoid_non_secure(15, '0123456789');
                RAISE NOTICE '%', generated_id;
                ASSERT LENGTH(generated_id) = 15, 'Size 15 (only numbers) nanoid_non_secure length is incorrect';
                ASSERT generated_id ~ '^[0-9]*$', 'Size 15 (only numbers) nanoid_non_secure contains invalid characters';
            END LOOP;

        -- Non-secure variant: a size smaller than 1 is rejected
        BEGIN
            generated_id := nanoid_non_secure(0);
            ASSERT FALSE, 'Size 0 was not rejected by nanoid_non_secure';
        EXCEPTION
            WHEN assert_failure THEN RAISE;
            WHEN raise_exception THEN NULL; -- expected rejection
        END;

        -- Non-secure variant: an empty alphabet is rejected
        BEGIN
            generated_id := nanoid_non_secure(21, '');
            ASSERT FALSE, 'Empty alphabet was not rejected by nanoid_non_secure';
        EXCEPTION
            WHEN assert_failure THEN RAISE;
            WHEN raise_exception THEN NULL; -- expected rejection
        END;

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