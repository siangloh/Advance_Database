CREATE OR REPLACE TRIGGER trg_check_finewaiver_and_discount
FOR INSERT OR UPDATE ON Fine
COMPOUND TRIGGER

    -- Variables for validation and discount checks
    v_usage_count NUMBER;
    v_max_usage NUMBER;
    v_sequence_num NUMBER;
    v_next_sequence NUMBER;
    v_existing_count NUMBER;
    v_is_member NUMBER(1);
    v_min_order_value NUMBER;
    v_max_discount NUMBER;
    v_end_date DATE;
    v_current_date DATE := TRUNC(SYSDATE);
    v_month_year VARCHAR2(4);
    v_current_month_year VARCHAR2(4);
    v_user_id VARCHAR2(9);
    v_discount_id VARCHAR2(9);
    v_fine_id VARCHAR2(9);
    v_voucher_id VARCHAR2(15);
    v_status VARCHAR2(10);
    -- Add collection to store data needed for validation
    TYPE t_voucher_usage_rec IS RECORD (
        userId VARCHAR2(9),
        voucherId VARCHAR2(15),
        fineId VARCHAR2(9),
        fineAmount NUMBER,
        discountApplied NUMBER
    );
    
    -- Add a collection for user ID lookup
    TYPE t_user_rec IS RECORD (
        fineId Fine.fineId%TYPE,
        userId VARCHAR2(9)
    );
    
    TYPE t_user_tab IS TABLE OF t_user_rec INDEX BY VARCHAR2(9); -- Indexed by fineId
    v_user_map t_user_tab;
    
    TYPE t_voucher_usage_tab IS TABLE OF t_voucher_usage_rec INDEX BY BINARY_INTEGER;
    v_voucher_usages t_voucher_usage_tab;
    v_row_count NUMBER := 0;
    
    -- Local procedure to format output
    PROCEDURE print_line(p_title VARCHAR2, p_val VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(p_title, 25) || ': ' || p_val);
    END;
    
    -- Validate fineId pattern
    PROCEDURE validate_fineId IS
        v_fineId VARCHAR2(9);
    BEGIN
        v_fineId := TRIM(:NEW.fineId);
        IF v_fineId IS NULL THEN
            RAISE_APPLICATION_ERROR(-20108, 'fineId cannot be null');
        ELSIF LENGTH(v_fineId) != 9 THEN
            RAISE_APPLICATION_ERROR(-20108, 'fineId must be exactly 9 characters long');
        ELSIF SUBSTR(v_fineId, 1, 1) != 'F' THEN
            RAISE_APPLICATION_ERROR(-20109, 'fineId must start with F');
        END IF;
        
        -- Extract the numeric part and attempt to convert it
        BEGIN
            v_sequence_num := TO_NUMBER(SUBSTR(v_fineId, 2, 4));
        EXCEPTION
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20110, 'fineId must have numeric characters in positions 2-5');
        END;
        
        -- IMPORTANT CHANGE: Removed check against Fine table during update
        -- This was causing the mutating table error
    END validate_fineId;
    
    -- Extract sequence number and validate
    PROCEDURE validate_sequence_number IS
    BEGIN
        v_month_year := SUBSTR(:NEW.fineId, 6, 4);
        v_current_month_year := TO_CHAR(SYSDATE, 'MMYY');
        
        IF v_month_year != v_current_month_year THEN
            RAISE_APPLICATION_ERROR(-20111, 'fineId month/year must match current date. Expected: ' || v_current_month_year || ', Got: ' || v_month_year);
        END IF;
        
        -- Only check sequence for new insertions, not updates
        IF INSERTING THEN
            -- This is safe in BEFORE EACH ROW for INSERT because we're not modifying the table yet
            SELECT NVL(MAX(TO_NUMBER(SUBSTR(fineId, 2, 4))), 0) + 1
            INTO v_next_sequence
            FROM Fine
            WHERE fineId LIKE 'F____' || v_month_year;
            
            IF v_sequence_num != v_next_sequence THEN
                RAISE_APPLICATION_ERROR(-20114, 'Invalid sequence number. Expected: ' || v_next_sequence || ', Got: ' || v_sequence_num);
            END IF;
        END IF;
    END validate_sequence_number;
    
    -- Check if fine already exists for borrowId
    PROCEDURE check_existing_fine IS
    v_existing_count NUMBER;
    v_borrow_exists NUMBER;
    BEGIN
        IF INSERTING THEN
            -- 1. Validate borrowId
            DECLARE
                v_exists NUMBER;
            BEGIN
                -- Check if the borrowId does NOT exist
                SELECT CASE WHEN EXISTS (
                    SELECT 1 FROM Borrowing WHERE borrowId = :NEW.borrowId
                ) THEN 1 ELSE 0 END
                INTO v_exists
                FROM dual;
                
                IF v_exists = 0 THEN
                    RAISE_APPLICATION_ERROR(-20005, 'Invalid borrowId: ' || :NEW.borrowId);
                END IF;
            END;
            
            -- 2. Check if the borrowId and copyId exist in BorrowingBooks
            SELECT COUNT(*)
            INTO v_borrow_exists
            FROM BorrowingBooks
            WHERE borrowId = :NEW.borrowId AND copyId = :NEW.copyId;
            
            IF v_borrow_exists = 0 THEN
                RAISE_APPLICATION_ERROR(-20131, 'Invalid borrowId or copyId: does not exist in BorrowingBooks.');
            END IF;
            
            -- 3. Check for duplicate fines (excluding Cancelled)
            -- This is safe in BEFORE EACH ROW for INSERT because we're not modifying the table yet
            SELECT COUNT(*)
            INTO v_existing_count
            FROM Fine f
            WHERE f.borrowId = :NEW.borrowId
            AND f.copyId = :NEW.copyId;
            
            IF v_existing_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20130, 'A fine already exists for this borrowId and copyId.');
            END IF;
        END IF;
    END check_existing_fine;
    
    -- Fetch campaign details and validate
    PROCEDURE validate_campaign IS
    BEGIN
        -- Only validate voucher if one is provided
        IF :NEW.voucherId IS NOT NULL THEN
            BEGIN
                -- Get voucher and discount details in a single query
                SELECT
                    d.maxUsagePerUser,
                    d.minimumOrderValue,
                    d.maxDiscountAmount,
                    v.endDate,
                    v.isMember,
                    d.discountId
                INTO
                    v_max_usage,
                    v_min_order_value,
                    v_max_discount,
                    v_end_date,
                    v_is_member,
                    v_discount_id
                FROM
                    Voucher v
                    JOIN Discount d ON v.discountId = d.discountId
                WHERE
                    v.voucherId = :NEW.voucherId;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20004, 'Invalid voucher ID: ' || :NEW.voucherId);
            END;
            
            -- Validate voucher conditions
            IF v_end_date < v_current_date THEN
                RAISE_APPLICATION_ERROR(-20001, 'The voucher expired on ' || TO_CHAR(v_end_date, 'YYYY-MM-DD') || ' and is not allowed to use.');
            END IF;
            
            IF :NEW.fineAmount < v_min_order_value THEN
                RAISE_APPLICATION_ERROR(-20002, 'The fine amount (RM ' || :NEW.fineAmount || ') does not meet the minimum order value (RM ' || v_min_order_value || ') for the campaign.');
            END IF;
            
            -- Check membership requirement if applicable
            IF v_is_member = 1 THEN
                DECLARE
                    v_member_check NUMBER;
                BEGIN
                    SELECT COUNT(*) INTO v_member_check
                    FROM Membership
                    WHERE userId = v_user_id
                    AND status = 'Active';
                    
                    IF v_member_check = 0 THEN
                        RAISE_APPLICATION_ERROR(-20006, 'This voucher requires an active membership.');
                    END IF;
                END;
            END IF;
            
            -- Add to voucher usage collection for AFTER STATEMENT validation
            v_row_count := v_row_count + 1;
            v_voucher_usages(v_row_count).userId := v_user_id;
            v_voucher_usages(v_row_count).voucherId := :NEW.voucherId;
            v_voucher_usages(v_row_count).fineId := :NEW.fineId;
            v_voucher_usages(v_row_count).fineAmount := :NEW.fineAmount;
            v_voucher_usages(v_row_count).discountApplied := :NEW.discountApplied;
        END IF;
    END validate_campaign;
    
    -- Validate fine status transitions
    PROCEDURE validate_status_change IS
    BEGIN
        -- For updates only
        IF UPDATING AND :OLD.status != :NEW.status THEN
            -- Prevent changing from 'Paid' to any other status
            IF :OLD.status = 'Paid' THEN
                RAISE_APPLICATION_ERROR(-20008, 'Cannot change status from Paid to ' || :NEW.status);
            END IF;
            
            -- Validate specific status transitions
            CASE :NEW.status
                WHEN 'Paid' THEN
                    -- Ensure fine amount is recorded when marking as paid
                    IF :NEW.paymentDate IS NULL THEN
                        :NEW.paymentDate := SYSDATE;
                    END IF;
                ELSE
                    NULL; -- Other status changes are allowed
            END CASE;
        END IF;
    END validate_status_change;

    PROCEDURE validate_duplicated_transaction(p_fine_id IN VARCHAR2) IS
        v_existing_count NUMBER;
        v_transaction_id VARCHAR2(50);
        
        -- Nested helper function (only visible within this procedure)
        FUNCTION get_transaction_id(p_fine_id IN VARCHAR2) RETURN VARCHAR2 IS
            v_txn_id VARCHAR2(50);
        BEGIN
            SELECT transactionId INTO v_txn_id
            FROM Transaction
            WHERE fineId = p_fine_id
            AND ROWNUM = 1;
            
            RETURN v_txn_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN 'UNKNOWN';
        END get_transaction_id;
    BEGIN
        -- First validate input parameter
        IF p_fine_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20000, 'Fine ID cannot be null');
        END IF;
        
        -- Check if a transaction already exists for this fine
        SELECT COUNT(*)
        INTO v_existing_count
        FROM Transaction
        WHERE fineId = p_fine_id;
            DBMS_OUTPUT.PUT_LINE('Transaction and invoice creation aborted.');
        
        -- If count > 0, then a transaction already exists
        IF v_existing_count > 0 THEN
            -- Get the existing transaction ID for more informative error
            v_transaction_id := get_transaction_id(p_fine_id);
            
            DBMS_OUTPUT.PUT_LINE('Error: This fine (ID: ' || p_fine_id || ') has already been paid');
            DBMS_OUTPUT.PUT_LINE('Existing transaction ID: ' || v_transaction_id);
            DBMS_OUTPUT.PUT_LINE('Transaction and invoice creation aborted.');
            
            -- RAISE_APPLICATION_ERROR(-20001, 
            --     'A transaction (ID: ' || v_transaction_id || 
            --     ') already exists for fine ID ' || p_fine_id);
            RAISE_APPLICATION_ERROR(-20001, 'You are not allowed to adjust the voucher.');
        END IF;
    END validate_duplicated_transaction;
    
    -- BEFORE STATEMENT section to initialize
    BEFORE STATEMENT IS
    BEGIN
        v_voucher_usages.DELETE;
        v_row_count := 0;
        
        -- IMPORTANT CHANGE: Move user ID pre-loading to a context/global table
        -- This avoids querying Fine during the trigger execution
    END BEFORE STATEMENT;
    
    -- BEFORE EACH ROW Section
    BEFORE EACH ROW IS
        -- Local variables for this row
        l_user_id VARCHAR2(9);
    BEGIN
        -- Basic validations first
        validate_fineId;
        validate_sequence_number;
        
        -- For INSERT operations, get user ID directly
        IF INSERTING THEN
            check_existing_fine;
            
            -- For new records, get userId from related tables
            BEGIN
                SELECT br.userId INTO l_user_id
                FROM Borrowing br
                WHERE br.borrowId = :NEW.borrowId;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20005, 'Invalid borrowId: ' || :NEW.borrowId);
            END;
        ELSE
            -- For UPDATE operations, we need a different approach to avoid querying Fine
            -- Get the userId directly from joined tables without querying Fine
            BEGIN
                SELECT br.userId INTO l_user_id
                FROM Borrowing br
                JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
                WHERE bb.borrowId = :NEW.borrowId AND bb.copyId = :NEW.copyId;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20005, 'Unable to find userId for this fine');
                WHEN TOO_MANY_ROWS THEN
                    -- Just take the first one if there are multiple (shouldn't happen if data is consistent)
                    SELECT br.userId INTO l_user_id
                    FROM Borrowing br
                    JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
                    WHERE bb.borrowId = :NEW.borrowId AND bb.copyId = :NEW.copyId
                    AND ROWNUM = 1;
            END;
        END IF;
        -- Capture the status before change
        IF UPDATING AND :OLD.voucherId IS NOT NULL AND :NEW.voucherId IS NULL THEN
            v_status := :OLD.status;
        END IF;
        -- Save the user ID for this row
        v_user_id := l_user_id;
        
        validate_campaign;
        validate_status_change;
        validate_duplicated_transaction(:NEW.fineId);
    END BEFORE EACH ROW;
    
    -- AFTER STATEMENT section for validations that would cause mutating table
    AFTER STATEMENT IS
    BEGIN
    IF v_status = 'Paid' THEN
            RAISE_APPLICATION_ERROR(-20006, 'You are not allowed to adjust!');
        END IF;
        -- Process voucher usage counts
        FOR i IN 1..v_row_count LOOP
            -- Get user voucher usage count
            SELECT COUNT(*)
            INTO v_usage_count
            FROM Fine f
            JOIN Borrowing b ON f.borrowId = b.borrowId
            WHERE f.voucherId = v_voucher_usages(i).voucherId
            AND b.userId = v_voucher_usages(i).userId
            AND f.status = 'Paid';
            
            -- Get max usage allowed
            SELECT d.maxUsagePerUser
            INTO v_max_usage
            FROM Voucher v
            JOIN Discount d ON v.discountId = d.discountId
            WHERE v.voucherId = v_voucher_usages(i).voucherId;
            
            -- Check if the count exceeds maximum
            IF v_usage_count > v_max_usage THEN
                RAISE_APPLICATION_ERROR(
                    -20003,
                    'User ' || v_voucher_usages(i).userId ||
                    ' exceeded max usage (' || v_max_usage || ') for voucher ' ||
                    v_voucher_usages(i).voucherId
                );
            END IF;
            
            -- Store the fine ID for possible use with ApplyVoucher
            v_fine_id := v_voucher_usages(i).fineId;
            v_voucher_id := v_voucher_usages(i).voucherId;
        END LOOP;
        IF v_row_count > 0 AND v_fine_id IS NOT NULL AND v_voucher_id IS NOT NULL THEN
            IF NOT global_vars_pkg.get_is_processing THEN 
                ApplyVoucher(v_fine_id, v_voucher_id, 'Cash');
                NULL;
                global_vars_pkg.set_is_processing(FALSE);
                global_vars_pkg.Set_is_updated;
            END IF;
      
        END IF;
    END AFTER STATEMENT;

END trg_check_finewaiver_and_discount;
/