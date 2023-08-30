DO
$$
    DECLARE
        startTime   timestamp;
        endTime     timestamp;
        durationA   interval;
        durationB   interval;
        numLoops    int := 1000000;
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
