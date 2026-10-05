-- Scenario 2: Computer Laboratory Reservations

DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

-- STEP 1: Create tables and add at least three sessions
CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id     INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer       VARCHAR(100) NOT NULL,
    workstations   INT NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 Programming Lab', 30),
    ('Tuesday 10:00 Networking Lab', 8),
    ('Wednesday 14:00 Database Lab', 0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- STEP 2: IF / ELSIF / ELSE session capacity report
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL', rec.session_name;
        ELSIF rec.available_workstations <= 10 THEN
            RAISE NOTICE '% : NEARLY FULL (% workstations left)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : ENOUGH workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', n;
    END LOOP;
END $$;

-- STEP 4: reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_qty THEN
        RAISE EXCEPTION 'Capacity exceeded for session %: requested %, available %',
            p_session_id, p_qty, v_available;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_qty, 'RESERVED');

    RAISE NOTICE 'Reservation recorded: % reserved % workstation(s) in session %',
        p_lecturer, p_qty, p_session_id;
END $$;

-- STEP 5: Two valid reservations and one exceeding capacity
DO $$
BEGIN
    BEGIN
        CALL reserve_workstations(1, 'Dr. Banda', 10);    -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Reservation failed: %', SQLERRM;
    END;

    BEGIN
        CALL reserve_workstations(2, 'Mr. Phiri', 5);     -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Reservation failed: %', SQLERRM;
    END;

    BEGIN
        CALL reserve_workstations(2, 'Ms. Mwansa', 10);   -- exceeds capacity
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Reservation failed: %', SQLERRM;
    END;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 6: cancel_reservation procedure (safe to call twice)
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty        INT;
    v_status     VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status INTO v_session_id, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % was already cancelled. No workstations released.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstation(s) released.', p_reservation_id, v_qty;
END $$;

CALL cancel_reservation(1);   -- first call releases workstations
CALL cancel_reservation(1);   -- second call must not release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 7: Explicit cursor for sessions with few workstations remaining
DO $$
DECLARE
    v_threshold INT := 10;
    cur_low CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions WHERE available_workstations <= v_threshold ORDER BY session_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: % (id %) - % remaining',
            rec.session_name, rec.session_id, rec.available_workstations;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: Zero workstations handled with an EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final availability and reservation statuses
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
