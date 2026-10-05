-- Scenario 4: Campus Clinic Medicine Dispensing

DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

-- STEP 1: Create tables and add at least three medicines
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol', 100),
    ('Amoxicillin', 15),
    ('Artemether', 0);

SELECT * FROM medicines ORDER BY medicine_id;

-- STEP 2: IF / ELSIF / ELSE stock status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 20 THEN
            RAISE NOTICE '% : LOW on stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Stock review day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', n;
    END LOOP;
END $$;

-- STEP 4: dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Insufficient stock for medicine %: requested %, in stock %',
            p_medicine_id, p_qty, v_stock;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student, p_qty, 'DISPENSED');

    RAISE NOTICE 'Dispensed % unit(s) of medicine % to student %', p_qty, p_medicine_id, p_student;
END $$;

-- STEP 5: Two valid quantities and one exceeding stock
DO $$
BEGIN
    BEGIN
        CALL dispense_medicine(1, '2024001', 20);   -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Dispensing failed: %', SQLERRM;
    END;

    BEGIN
        CALL dispense_medicine(2, '2024002', 5);    -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Dispensing failed: %', SQLERRM;
    END;

    BEGIN
        CALL dispense_medicine(2, '2024003', 50);   -- exceeds stock
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Dispensing failed: %', SQLERRM;
    END;
END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 6: reverse_dispensing procedure (stock restored only once)
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % was already reversed. Stock not restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed. % unit(s) restored to stock.', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(1);   -- first call restores stock
CALL reverse_dispensing(1);   -- second call must not restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 7: Explicit cursor for medicines below a low-stock threshold
DO $$
DECLARE
    v_threshold INT := 20;
    cur_low CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines WHERE stock_quantity < v_threshold ORDER BY medicine_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % - % in stock',
            v_threshold, rec.medicine_name, rec.stock_quantity;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: Negative quantity handled with an EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '2024004', -5);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final stock and dispensing statuses
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
