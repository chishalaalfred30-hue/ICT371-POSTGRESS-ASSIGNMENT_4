-- Scenario 3: Student Hostel Room Allocation

DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;

-- STEP 1: Create tables and add at least three rooms
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_name        VARCHAR(20) NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- STEP 2: IF / ELSIF / ELSE room status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % : FULL', rec.room_name;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % : ONE SPACE LEFT', rec.room_name;
        ELSE
            RAISE NOTICE 'Room % : SEVERAL SPACES (%)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', n;
    END LOOP;
END $$;

-- STEP 4: allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_room_id INT, p_student VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student IS NULL OR TRIM(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE EXCEPTION 'Room % is full. No space available', p_room_id;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (TRIM(p_student), p_room_id, 'ALLOCATED');

    RAISE NOTICE 'Student % allocated to room %', p_student, p_room_id;
END $$;

-- STEP 5: Two valid allocations and one to a full room
DO $$
BEGIN
    BEGIN
        CALL allocate_room(1, '2024001');   -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Allocation failed: %', SQLERRM;
    END;

    BEGIN
        CALL allocate_room(2, '2024002');   -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Allocation failed: %', SQLERRM;
    END;

    BEGIN
        CALL allocate_room(3, '2024003');   -- full room
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Allocation failed: %', SQLERRM;
    END;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- STEP 6: check_out procedure (safe to call twice)
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out. No space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out. One bed space released.', p_allocation_id;
END $$;

CALL check_out(1);   -- first call frees one space
CALL check_out(1);   -- second call must not free another

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- STEP 7: Explicit cursor for full or nearly full rooms
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_id, room_name, available_spaces
        FROM hostel_rooms WHERE available_spaces <= 1 ORDER BY room_id;
    rec RECORD;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO rec;
        EXIT WHEN NOT FOUND;
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', rec.room_name;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- STEP 8: Blank student number handled with an EXCEPTION block
DO $$
BEGIN
    CALL allocate_room(1, '   ');
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final available spaces and allocation statuses
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
