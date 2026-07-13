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

-- The whole install/upgrade runs in one transaction: if any statement fails (for example a
-- DROP blocked by objects that depend on an old function signature), everything rolls back
-- and the database keeps its previous, fully working installation.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- The `nanoid()` function generates a compact, URL-friendly unique identifier.
-- Based on the given size and alphabet, it creates a randomized string that's ideal for
-- use-cases requiring small, unpredictable IDs (e.g., URL shorteners, generated file names, etc.).
-- While it comes with a default configuration, the function is designed to be flexible,
-- allowing for customization to meet specific needs.
-- The 2022-era signature nanoid(int, text) is dropped so positional calls stay unambiguous after
-- an upgrade. The current signature is intentionally NOT dropped: CREATE OR REPLACE upgrades it
-- in place, which also works when objects (e.g. column defaults) depend on the function.
DROP FUNCTION IF EXISTS nanoid(int, text);
CREATE OR REPLACE FUNCTION nanoid(
    size int DEFAULT 21, -- The number of symbols in the NanoId String. Must be greater than 0.
    alphabet text DEFAULT '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', -- The symbols used in the NanoId String. Must contain between 1 and 255 symbols.
    additionalBytesFactor float DEFAULT 1.6 -- The additional bytes factor used for calculating the step size. Acts as a safety margin for rejected bytes. Must be equal or greater then 1.
)
    RETURNS text -- A randomly generated NanoId String
    LANGUAGE plpgsql
    VOLATILE
    -- PL/pgSQL advances the command counter and takes new snapshots when evaluating volatile expressions,
    -- which is forbidden in parallel mode ("cannot start commands during a parallel operation", see issue #16).
    PARALLEL UNSAFE
    -- Uncomment the following line if you have superuser privileges
    -- LEAKPROOF
AS
$$
DECLARE
    alphabetLength int;
    cutoff         int;
    step           int;
BEGIN
    IF size IS NULL OR size < 1 THEN
        RAISE EXCEPTION 'The size must be defined and greater than 0!';
    END IF;

    IF alphabet IS NULL OR length(alphabet) = 0 OR length(alphabet) > 255 THEN
        RAISE EXCEPTION 'The alphabet can''t be undefined, zero or bigger than 255 symbols!';
    END IF;

    IF additionalBytesFactor IS NULL OR additionalBytesFactor < 1 THEN
        RAISE EXCEPTION 'The additional bytes factor can''t be less than 1!';
    END IF;

    alphabetLength := length(alphabet);
    -- Random bytes are 0-255. `byte % alphabetLength` would make some symbols more likely
    -- when 256 is not a multiple of the alphabet length. Bytes greater than or equal to
    -- `cutoff` are rejected instead, so every symbol keeps an equal chance.
    cutoff := 256 - (256 % alphabetLength);
    -- On average `256 / cutoff` random bytes are needed per symbol; the additional bytes
    -- factor adds a safety margin to cover unlucky streaks of rejected bytes.
    -- gen_random_bytes() accepts at most 1024 bytes per call; capping before the int cast
    -- also keeps absurd sizes from overflowing the cast.
    step := cast(least(1024, ceil(additionalBytesFactor * 256 * size / cutoff)) AS int);

    RETURN nanoid_optimized(size, alphabet, cutoff, step);
END
$$;

-- Generates an optimized random string of a specified size using the given alphabet, cutoff, and step.
-- This optimized version is designed for higher performance and lower memory overhead.
-- No checks are performed! Use it only if you really know what you are doing.
-- The drop is required because the third parameter was renamed (mask -> cutoff) and
-- CREATE OR REPLACE cannot rename parameters. If dependent objects block the drop, the
-- transaction rolls back; see the Upgrading section of the README.
DROP FUNCTION IF EXISTS nanoid_optimized(int, text, int, int);
CREATE OR REPLACE FUNCTION nanoid_optimized(
    size int, -- The desired length of the generated string.
    alphabet text, -- The set of characters to choose from for generating the string.
    cutoff int, -- The exclusive upper bound for accepted random bytes. Should be `256 - (256 % alphabetLength)`; bytes greater than or equal to it are rejected to avoid modulo bias.
    step int -- The number of random bytes to generate in each iteration. A larger value may speed up the function but increase memory usage.
)
    RETURNS text -- A randomly generated NanoId String
    LANGUAGE plpgsql
    VOLATILE
    -- PL/pgSQL advances the command counter and takes new snapshots when evaluating volatile expressions,
    -- which is forbidden in parallel mode ("cannot start commands during a parallel operation", see issue #16).
    PARALLEL UNSAFE
    -- Uncomment the following line if you have superuser privileges
    -- LEAKPROOF
AS
$$
DECLARE
    idBuilder      text := '';
    counter        int  := 0;
    bytes          bytea;
    randomByte     int;
    alphabetArray  text[];
    alphabetLength int;
BEGIN
    alphabetArray := regexp_split_to_array(alphabet, '');
    alphabetLength := array_length(alphabetArray, 1);

    LOOP
        bytes := gen_random_bytes(step);
        FOR counter IN 0..step - 1
            LOOP
                randomByte := get_byte(bytes, counter);
                IF randomByte < cutoff THEN
                    idBuilder := idBuilder || alphabetArray[(randomByte % alphabetLength) + 1];
                    IF length(idBuilder) = size THEN
                        RETURN idBuilder;
                    END IF;
                END IF;
            END LOOP;
    END LOOP;
END
$$;

COMMIT;
