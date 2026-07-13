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
        generated_id text;
        counter      int;
        numLoops     int := 1000;
        alphabet256  text;
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