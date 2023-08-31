DO
$$
    DECLARE
        generated_id text;
        counter      int;
        numLoops     int := 1000;
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