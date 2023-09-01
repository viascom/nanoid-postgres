DO
$$
    DECLARE
        startTime   timestamp;
        endTime     timestamp;
        durationA   interval;
        durationB   interval;
        numLoops    int := 100000;
        counter     int;
        dummyResult text;
    BEGIN

        -- Benchmarking A nanoid()
        RAISE NOTICE '-----------------------------';
        RAISE NOTICE 'Starting benchmark for A nanoid() for % loops...', numLoops;
        startTime := clock_timestamp();
        FOR counter IN 1..numLoops
            LOOP
                dummyResult := a_nanoid();
                dummyResult := a_nanoid(5, '23456789abcdefghijklmnopqrstuvwxyz');
                dummyResult := a_nanoid(11, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,');
                dummyResult := a_nanoid(48, '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ');
            END LOOP;
        endTime := clock_timestamp();
        durationA := endTime - startTime;
        RAISE NOTICE 'A nanoid() took %', durationA;
        RAISE NOTICE '-----------------------------';

        -- Benchmarking B nanoid()
        RAISE NOTICE 'Starting benchmark for B nanoid() for % loops...', numLoops;
        startTime := clock_timestamp();
        FOR counter IN 1..numLoops
            LOOP
                dummyResult := b_nanoid();
                dummyResult := b_nanoid(5, '23456789abcdefghijklmnopqrstuvwxyz');
                dummyResult := b_nanoid(11, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,');
                dummyResult := b_nanoid(48, '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ');
            END LOOP;
        endTime := clock_timestamp();
        durationB := endTime - startTime;
        RAISE NOTICE 'B nanoid() took %', durationB;
        RAISE NOTICE '-----------------------------';

        -- Compare
        IF durationA < durationB THEN
            RAISE NOTICE 'A nanoid() is faster by %', durationB - durationA;
        ELSIF durationA > durationB THEN
            RAISE NOTICE 'B nanoid() is faster by %', durationA - durationB;
        ELSE
            RAISE NOTICE 'Both functions have comparable performance.';
        END IF;

        RAISE NOTICE '-----------------------------';

    END
$$;

-- TODO:
-- EXTRACT(EPOCH FROM (timestamp1 - timestamp2))
-- ROUND()