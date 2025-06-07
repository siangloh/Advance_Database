CREATE OR REPLACE TRIGGER trg_user_reservation_cancellations
BEFORE INSERT ON Borrowing
FOR EACH ROW
DECLARE
    v_cancel_count NUMBER := 0;
    v_user_exists NUMBER := 0;
    v_sequence_num NUMBER := 0;
    v_next_sequence NUMBER := 1;
    v_reserved_count NUMBER := 0;
    v_month_year VARCHAR2(4);
    v_current_month_year VARCHAR2(4);
    v_month_start DATE;
    v_next_month_start DATE;
    v_borrowId VARCHAR2(10);  -- Changed from 9 to 10 to match expected length
    
    -- Constants for better maintainability
    c_max_cancellations CONSTANT NUMBER := 3;
    c_max_reservations CONSTANT NUMBER := 3;
    c_prefix CONSTANT VARCHAR2(2) := 'BR';
    
    -- Valid status values
    TYPE status_array IS TABLE OF VARCHAR2(10) INDEX BY PLS_INTEGER;
    v_valid_statuses status_array;
BEGIN
    -- Initialize valid statuses
    v_valid_statuses(1) := 'Reserved';
    v_valid_statuses(2) := 'Borrowed';
    v_valid_statuses(3) := 'Returned';
    v_valid_statuses(4) := 'Overdue';
    v_valid_statuses(5) := 'Cancelled';
    v_valid_statuses(6) := 'RBorrowed';

    -- Set common date range values once
    v_month_start := TRUNC(SYSDATE, 'MM');
    v_next_month_start := TRUNC(ADD_MONTHS(SYSDATE, 1), 'MM');
    v_current_month_year := TO_CHAR(SYSDATE, 'MMYY');

    -- 1. Validate borrowId
    -- Comprehensive borrowId validation block
    BEGIN
        v_borrowId := TRIM(:NEW.borrowId);  -- Fixed: Using := instead of =
        
        -- Check for null
        IF v_borrowId IS NULL THEN
            RAISE_APPLICATION_ERROR(-20008, 'borrowId cannot be null');
        END IF;
        
        -- Check length
        IF LENGTH(v_borrowId) != 10 THEN
            RAISE_APPLICATION_ERROR(-20008, 'borrowId must be exactly 10 characters long');
        END IF;
        
        -- Check prefix
        IF SUBSTR(v_borrowId, 1, 2) != c_prefix THEN
            RAISE_APPLICATION_ERROR(-20009, 'borrowId must start with ' || c_prefix);
        END IF;
        
        -- Extract and validate sequence number
        BEGIN
            v_sequence_num := TO_NUMBER(SUBSTR(v_borrowId, 3, 4));
        EXCEPTION
            WHEN VALUE_ERROR THEN
                RAISE_APPLICATION_ERROR(-20012, 'Sequence part (positions 3-6) must be numeric');
        END;
        
        -- Extract and validate month/year
        v_month_year := SUBSTR(v_borrowId, 7, 4);
        IF NOT REGEXP_LIKE(v_month_year, '^[0-9]{4}$') THEN
            RAISE_APPLICATION_ERROR(-20019, 'Month/year part (positions 7-10) must be 4 digits');
        END IF;
        
        -- Validate month/year against current date
        IF v_month_year != v_current_month_year THEN
            RAISE_APPLICATION_ERROR(-20010, 'borrowId month/year must match current date (expected ' || 
                v_current_month_year || ' but got ' || v_month_year || ')');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20020, 'Error validating borrowId format: ' || SQLERRM);
    END;

    -- [Rest of your trigger code remains the same...]
    
    -- 2. Get next sequence number and validate sequence
    BEGIN
        SELECT NVL(MAX(TO_NUMBER(SUBSTR(borrowId, 3, 4))), 0) + 1
        INTO v_next_sequence
        FROM Borrowing
        WHERE borrowId LIKE c_prefix || '____' || v_current_month_year;
        
        -- Only enforce sequence for non-cancellations
        IF :NEW.status != 'Cancelled' AND v_sequence_num != v_next_sequence THEN
            RAISE_APPLICATION_ERROR(-20014, 'Invalid sequence number. Expected ' || 
                v_next_sequence || ' but got ' || v_sequence_num);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20015, 'Error checking or validating sequence numbers: ' || SQLERRM);
    END;

    -- 3. Check user exists
    BEGIN
        SELECT COUNT(*) INTO v_user_exists
        FROM "User"
        WHERE userId = :NEW.userId;
        
        IF v_user_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid user. User ID does not exist.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20016, 'Error checking user existence: ' || SQLERRM);
    END;

    -- 4. Validate status using the array
    DECLARE
        v_status_valid BOOLEAN := FALSE;
    BEGIN
        FOR i IN 1..v_valid_statuses.COUNT LOOP
            IF :NEW.status = v_valid_statuses(i) THEN
                v_status_valid := TRUE;
                EXIT;
            END IF;
        END LOOP;
        
        IF NOT v_status_valid THEN
            RAISE_APPLICATION_ERROR(-20006, 'Invalid status value. Must be one of: Reserved, Borrowed, Returned, Overdue, Cancelled, RBorrowed');
        END IF;
    END;

    -- 5. Check cancellations this month
    BEGIN
        SELECT COUNT(*) INTO v_cancel_count
        FROM Borrowing
        WHERE userId = :NEW.userId
        AND status = 'Cancelled'
        AND dateBorrow >= v_month_start
        AND dateBorrow < v_next_month_start;
        
        IF v_cancel_count >= c_max_cancellations THEN
            RAISE_APPLICATION_ERROR(-20005, 'Borrowing restricted due to ' || c_max_cancellations || ' or more cancellations this month.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20017, 'Error checking cancellation history: ' || SQLERRM);
    END;
        
    -- 6. Additional check for reservations only
    IF :NEW.status = 'Reserved' THEN
        BEGIN
            SELECT COUNT(*) INTO v_reserved_count
            FROM Borrowing
            WHERE userId = :NEW.userId
            AND status IN ('Reserved', 'RBorrowed')
            AND dateBorrow >= v_month_start
            AND dateBorrow < v_next_month_start;
            
            IF v_reserved_count >= c_max_reservations THEN
                RAISE_APPLICATION_ERROR(-20013, 'You have already made ' || c_max_reservations || 
                    ' reservations this month. Please wait until next month to reserve more books.');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20018, 'Error checking reservation count: ' || SQLERRM);
        END;
    END IF;
END;
/