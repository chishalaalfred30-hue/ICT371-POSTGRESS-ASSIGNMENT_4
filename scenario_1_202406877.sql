-- Scenario 1: University Library Book Loans

DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

-- STEP 1: Create tables and add at least three books
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL,
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
);

INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 5),
    ('Data Structures and Algorithms', 2),
    ('Computer Networks', 0);

SELECT * FROM books ORDER BY book_id;

-- STEP 2: IF / ELSIF / ELSE stock status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% : UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '% : LOW on copies (% left)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE loop and numeric FOR loop
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', counter;
        counter := counter + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;

-- STEP 4: borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_copies INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_copies INTO v_copies
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_copies < p_qty THEN
        RAISE EXCEPTION 'Not enough copies of book %: requested %, available %',
            p_book_id, p_qty, v_copies;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student, p_qty, 'BORROWED');

    RAISE NOTICE 'Loan recorded: student % borrowed % copy(ies) of book %',
        p_student, p_qty, p_book_id;
END $$;

-- STEP 5: Two valid loans and one request exceeding available copies
DO $$
BEGIN
    BEGIN
        CALL borrow_book(1, '2024001', 2);   -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Loan failed: %', SQLERRM;
    END;

    BEGIN
        CALL borrow_book(2, '2024002', 1);   -- valid
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Loan failed: %', SQLERRM;
    END;

    BEGIN
        CALL borrow_book(2, '2024003', 5);   -- exceeds available copies
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Loan failed: %', SQLERRM;
    END;
END $$;

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- STEP 6: return_book procedure (safe to call twice)
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy(ies) restored.', p_loan_id, v_qty;
END $$;

CALL return_book(1);   -- first call restores copies
CALL return_book(1);   -- second call must not restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- STEP 7: Explicit cursor for books with few copies remaining
DO $$
DECLARE
    v_threshold INT := 2;
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books WHERE available_copies <= v_threshold ORDER BY book_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left: % (id %) - % copy(ies)',
            rec.title, rec.book_id, rec.available_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: Zero copies handled with an EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '2024004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final quantities and loan statuses
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
