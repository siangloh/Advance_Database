-- Reset any previous formatting
SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF

ALTER TABLE Transaction ADD created_date TIMESTAMP DEFAULT SYSTIMESTAMP;

-- Create a package specification to hold global variables
CREATE OR REPLACE PACKAGE global_vars_pkg AS
  -- Boolean variables (Oracle uses NUMBER(1) where 1=TRUE, 0=FALSE)
  g_is_processing NUMBER(1);
  g_is_Update   NUMBER;
  
  -- Constants for true/false
  TRUE_CONSTANT  CONSTANT NUMBER(1) := 1;
  FALSE_CONSTANT CONSTANT NUMBER(1) := 0;
  
  -- Procedures to set values
  PROCEDURE set_is_processing(p_value IN BOOLEAN);
  PROCEDURE set_is_updated(p_value IN NUMBER);  -- New setter
  PROCEDURE reset_is_updated;
  -- Functions to get values
  FUNCTION get_is_processing RETURN BOOLEAN;
  FUNCTION get_is_updated RETURN NUMBER;        -- New getter
END global_vars_pkg;
/

-- Package Specification
CREATE OR REPLACE PACKAGE global_vars_pkg AS
  -- Boolean variables (Oracle uses NUMBER(1) where 1=TRUE, 0=FALSE)
  g_is_processing NUMBER(1);
  g_is_Update     NUMBER;
  
  -- Constants for true/false
  TRUE_CONSTANT  CONSTANT NUMBER(1) := 1;
  FALSE_CONSTANT CONSTANT NUMBER(1) := 0;
  
  -- Procedures to set values
  PROCEDURE set_is_processing(p_value IN BOOLEAN);
  PROCEDURE set_is_updated;  -- Changed to no parameter since it just increments
  PROCEDURE reset_is_updated;
  
  -- Functions to get values
  FUNCTION get_is_processing RETURN BOOLEAN;
  FUNCTION get_is_updated RETURN NUMBER;
END global_vars_pkg;
/

-- Package Body
CREATE OR REPLACE PACKAGE BODY global_vars_pkg AS
  -- Implement setter procedures
  PROCEDURE set_is_processing(p_value IN BOOLEAN) IS
  BEGIN
    IF p_value THEN
      g_is_processing := TRUE_CONSTANT;
    ELSE
      g_is_processing := FALSE_CONSTANT;
    END IF;
  END set_is_processing;
 
  PROCEDURE set_is_updated IS
  BEGIN
    g_is_Update := g_is_Update + 1;  -- Fixed assignment operator (= to :=)
  END set_is_updated;
  
  PROCEDURE reset_is_updated IS 
  BEGIN
    g_is_Update := 0;  -- Fixed assignment and variable name
  END reset_is_updated;

  -- Implement getter functions
  FUNCTION get_is_processing RETURN BOOLEAN IS
  BEGIN
    RETURN (g_is_processing = TRUE_CONSTANT);
  END get_is_processing;

  FUNCTION get_is_updated RETURN NUMBER IS 
  BEGIN
    RETURN g_is_Update;
  END get_is_updated;
  
BEGIN
  -- Initialize global variables when package is first loaded
  g_is_processing := FALSE_CONSTANT;
  g_is_Update := 0;  -- Initialize the counter
END global_vars_pkg;
/

-- Clear any existing variables
UNDEFINE fineIdInput
UNDEFINE voucherIdInput
UNDEFINE paymentMethodInput

SET SERVEROUTPUT ON 
SET VERIFY OFF      
SET DEFINE ON      
SET LINESIZE 150 

-- Prompt for user input
PROMPT
ACCEPT fineIdInput CHAR PROMPT 'Enter the Fine ID > '
ACCEPT voucherIdInput CHAR PROMPT 'Enter the Voucher ID > '
ACCEPT paymentMethodInput CHAR PROMPT 'Enter the Payment Method (Cash, Debit Card, Credit Card, PayPal, Bank Transfer, TNG) > '

DROP PROCEDURE ApplyVoucher;
CREATE OR REPLACE PROCEDURE ApplyVoucher(
    fineIdExist IN VARCHAR2,
    voucherIdApply IN VARCHAR2,
    paymentMethod IN VARCHAR2
) AS
    -- Main variables
    v_fine_amount NUMBER(10,2);
    v_discount_value NUMBER(10,2);
    v_is_percentage NUMBER(1);
    v_max_discount NUMBER(10,2);
    v_discount_applied NUMBER(10,2);
    v_final_amount NUMBER(10,2);
    v_campaign_name VARCHAR2(100);
    v_user_id VARCHAR2(20);
    v_user_name VARCHAR2(100);
    v_book_title VARCHAR2(200);
    v_copy_id VARCHAR2(20);
    v_borrow_id VARCHAR2(20);
    v_transaction_id VARCHAR2(20);
    v_invoice_id VARCHAR2(20);
    v_adminFee NUMBER(10,2) := 0;
    v_sst NUMBER(10,2) := 0;
    v_overdue_days NUMBER := 0;
    v_count_bookReturned NUMBER := 0;
    v_debug_step VARCHAR2(100) := 'Initializing';
    v_library_name VARCHAR2(100) := 'LIBRARY SYSTEM';
    v_library_address VARCHAR2(200) := '123 ABC SDN BHD';
    v_library_contact VARCHAR2(100) := 'Tel: (01) 234-5678 | Email: ABClibrary@gmail.com';
    v_cashier VARCHAR2(50);
    v_isbn VARCHAR2(20);
    v_date_borrowed DATE;
    v_due_date DATE;
    v_current_time VARCHAR2(8);
    v_campaign_start_date DATE;
    v_campaign_end_date DATE;
    
    -- Exception definitions for better error handling
    e_campaign_not_found EXCEPTION;
    e_fine_not_found EXCEPTION;
    e_campaign_inactive EXCEPTION;

    -- Local function to get campaign details
    PROCEDURE get_campaign_details IS
    BEGIN
        SELECT fw.voucherName, d.discountValue, d.isPercentage, d.maxDiscountAmount,
               fw.startDate, fw.endDate
        INTO v_campaign_name, v_discount_value, v_is_percentage, v_max_discount,
             v_campaign_start_date, v_campaign_end_date
        FROM Voucher fw
        JOIN Discount d ON fw.discountId = d.discountId
        WHERE fw.voucherId = voucherIdApply;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error retrieving campaign details');
            RAISE;
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Unexpected error getting campaign details: ' || SQLERRM);
            RAISE;
    END get_campaign_details;
    
    -- Local function to get fine details
    PROCEDURE get_fine_details IS
    BEGIN
        SELECT f.fineAmount, b.title, br.userId, f.copyId, f.borrowId, f.sst, f.adminFee,
               bn.isbnId, TO_NUMBER(NVL(TO_CHAR(TRUNC(f.paymentDate - br.duedate)), '0')) AS overdue_days,
               br.dateBorrow, br.duedate
        INTO v_fine_amount, v_book_title, v_user_id, v_copy_id, v_borrow_id, v_sst, v_adminFee,
             v_isbn, v_overdue_days, v_date_borrowed, v_due_date
        FROM Fine f
        JOIN BookOfCopies bc ON bc.copyId = f.copyId
        JOIN Book b ON bc.bookId = b.bookId
        JOIN ISBN bn ON bn.bookId = b.bookId
        JOIN Borrowing br ON f.borrowId = br.borrowId
        WHERE f.fineId = fineIdExist;
        
        -- Get user full name if available
        BEGIN
            SELECT username
            INTO v_user_name
            FROM "User"
            WHERE userId = v_user_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_user_name := v_user_id;
            WHEN OTHERS THEN
                v_user_name := v_user_id;
        END;
        
        -- Get current system user as cashier (if the table contains this information)
        BEGIN
            v_cashier := SYS_CONTEXT('USERENV', 'SESSION_USER');
        EXCEPTION
            WHEN OTHERS THEN
                v_cashier := 'System';
        END;
        
        -- Get current time
        v_current_time := TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS');
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Error retrieving fine details');
            RAISE;
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error getting fine details: ' || SQLERRM);
            RAISE;
    END get_fine_details;
    
    PROCEDURE validate_payment_method (
        p_payment_method IN VARCHAR2
    ) IS
        TYPE t_payment_methods IS TABLE OF VARCHAR2(20);
        v_valid_payment_methods t_payment_methods := t_payment_methods(
            'Cash', 'Credit Card', 'Debit Card', 'PayPal', 'Bank Transfer', 'TNG'
        );
        v_is_valid BOOLEAN := FALSE;
        v_method_list VARCHAR2(4000);
    BEGIN
        -- Check if payment method is null or empty
        IF p_payment_method IS NULL OR TRIM(p_payment_method) = '' THEN
            RAISE_APPLICATION_ERROR(-20001, 'Payment method cannot be null or empty');
        END IF;
    
        -- Build the list of valid methods
        FOR i IN 1..v_valid_payment_methods.COUNT LOOP
            IF i > 1 THEN
                v_method_list := v_method_list || ', ';
            END IF;
            v_method_list := v_method_list || v_valid_payment_methods(i);
            
            -- Check against valid methods (case-sensitive)
            IF UPPER(v_valid_payment_methods(i)) = UPPER(p_payment_method) THEN
                v_is_valid := TRUE;
            END IF;
        END LOOP;
    
        IF NOT v_is_valid THEN
            RAISE_APPLICATION_ERROR(-20002,
                'Invalid payment method: ' || p_payment_method ||
                '. Valid methods are: ' || v_method_list);
        END IF;
    
        DBMS_OUTPUT.PUT_LINE('Payment method ' || p_payment_method || ' is valid');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error validating payment method: ' || SQLERRM);
            RAISE;
    END validate_payment_method;

    -- Local function to calculate discount
    PROCEDURE calculate_discount IS
    BEGIN
        IF v_is_percentage = 1 THEN
            v_discount_applied := v_fine_amount * (v_discount_value / 100);
            IF v_max_discount IS NOT NULL AND v_discount_applied > v_max_discount THEN
                v_discount_applied := v_max_discount;
            END IF;
        ELSE
            v_discount_applied := LEAST(v_fine_amount, v_discount_value);
        END IF;

        IF v_discount_applied < 0 THEN
            v_discount_applied := 0;
        END IF;
    END calculate_discount;
    
    -- Local function to generate transaction and invoice IDs
    PROCEDURE generate_transaction_ids IS
        v_current_date CHAR(4);
        v_current_sequence NUMBER;
        v_last_id VARCHAR2(20);
        v_last_sequence NUMBER;
        v_last_date_part CHAR(4);
        v_current_year CHAR(2);
    BEGIN
        -- Get current month and year format
        v_current_date := TO_CHAR(SYSDATE, 'MM') || TO_CHAR(SYSDATE, 'YY');
        v_current_year := TO_CHAR(SYSDATE, 'YY');
        -- Get the last transaction ID
        BEGIN
        SELECT transactionId INTO v_last_id
        FROM (
            SELECT transactionId
            FROM transaction
            ORDER BY CREATED_DATE DESC
        )
        WHERE ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_last_id := NULL;
        END;
        
        -- Determine sequence number
        IF v_last_id IS NOT NULL THEN
            v_last_sequence := TO_NUMBER(SUBSTR(v_last_id, 2, 4));
            v_last_date_part := SUBSTR(v_last_id, 8, 2);            
            IF v_last_date_part != v_current_year THEN
                v_current_sequence := 1;
            ELSE
                v_current_sequence := v_last_sequence + 1;
            END IF;
        ELSE
            v_current_sequence := 1;
        END IF;
        -- Generate IDs
            DBMS_OUTPUT.PUT_LINE('Error generating transaction IDs: ' || v_current_sequence || ', ' || v_current_date || ', ' || v_last_id);
        v_transaction_id := 'T' || LPAD(TO_CHAR(v_current_sequence), 4, '0') || v_current_date;
        v_invoice_id := 'I' || LPAD(TO_CHAR(v_current_sequence), 4, '0') || v_current_date;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error generating transaction IDs: ' || SQLERRM);
            RAISE;
    END generate_transaction_ids;
    
    -- Local procedure to update book status
    PROCEDURE update_book_status IS
    BEGIN
        -- Update borrowing records
        UPDATE BorrowingBooks
        SET dateReturn = CURRENT_DATE
        WHERE borrowId = v_borrow_id AND copyId = v_copy_id;
        
        -- Update book copies
        UPDATE BookOfCopies
        SET status = 'Available'
        WHERE copyId = v_copy_id ;

        -- Check if all books are returned
        SELECT COUNT(*) INTO v_count_bookReturned
        FROM BorrowingBooks bb
        WHERE bb.borrowId = v_borrow_id AND bb.dateReturn IS NULL;

        IF v_count_bookReturned = 0 THEN
            UPDATE Borrowing
            SET status = 'Returned'
            WHERE borrowId = v_borrow_id;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error updating book status: ' || SQLERRM);
            RAISE;
    END update_book_status;
    
    -- Local procedure to print receipt
    PROCEDURE print_receipt IS
    -- Constants
        c_width NUMBER := 60;
        c_separator VARCHAR2(100);
        c_header_separator VARCHAR2(100);
        
        -- Function to create a divider line
        FUNCTION divider(char_type VARCHAR2, length NUMBER) RETURN VARCHAR2 IS
            result VARCHAR2(200);
        BEGIN
            result := RPAD(char_type, length, char_type);
            RETURN result;
        END divider;
        
        -- Function to center text
        FUNCTION center_text(text VARCHAR2, width NUMBER) RETURN VARCHAR2 IS
            text_length NUMBER := LENGTH(text);
            padding NUMBER := FLOOR((width - text_length) / 2);
        BEGIN
            RETURN LPAD(' ', padding) || text;
        END center_text;
                
    BEGIN
        c_separator := divider('-', c_width+6);
        c_header_separator := divider('=', c_width + 6);
        -- Header with library details
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '|' ||  c_header_separator || '|');
        DBMS_OUTPUT.PUT_LINE('|' || center_text(v_library_name, c_width) || LPAD('|', 0.5*c_width));
        DBMS_OUTPUT.PUT_LINE('|' || center_text(v_library_address, c_width) || LPAD('|', 0.5*c_width));
        DBMS_OUTPUT.PUT_LINE('|' || center_text(v_library_contact, c_width) || LPAD('|', 0.2*c_width+1));
        DBMS_OUTPUT.PUT_LINE('|' ||  c_header_separator || '|');
        DBMS_OUTPUT.PUT_LINE('|' || center_text('FINE PAYMENT RECEIPT', c_width)|| LPAD('|', 0.5*c_width-3));
        DBMS_OUTPUT.PUT_LINE('|' || c_separator || '|');
        
        -- Transaction details
        DBMS_OUTPUT.PUT_LINE('| Date: ' || TO_CHAR(CURRENT_DATE, 'DD-MON-YYYY') || RPAD(' ', 30) || 'Time: ' || v_current_time || LPAD('|',5));
        DBMS_OUTPUT.PUT_LINE('| Cashier: ' || v_cashier || LPAD('|', 53));
        DBMS_OUTPUT.PUT_LINE('| Transaction ID: ' || v_transaction_id || RPAD(' ', 20) || 'Invoice: ' || v_invoice_id || LPAD('|', 3));
        DBMS_OUTPUT.PUT_LINE('|' || c_separator || '|');
        
        -- User and book details
        DBMS_OUTPUT.PUT_LINE('| PATRON INFORMATION:' || LPAD('|', 47));
        DBMS_OUTPUT.PUT_LINE('|   ID: ' || v_user_id || LPAD('|', 51));
        DBMS_OUTPUT.PUT_LINE('|   Name: ' || RPAD(v_user_name, 37) || LPAD('|', 21));
        DBMS_OUTPUT.PUT_LINE('|' || c_separator || '|');
        
        DBMS_OUTPUT.PUT_LINE('| BOOK DETAILS:' || LPAD('|', 53));
        DBMS_OUTPUT.PUT_LINE('|   Title: ' || RPAD(v_book_title, 47) || LPAD('|', 10));
        DBMS_OUTPUT.PUT_LINE('|   Book ID: ' || RPAD(v_copy_id, 3) || RPAD(' ', 25) || 'ISBN: ' || v_isbn || LPAD('|', 4));
        DBMS_OUTPUT.PUT_LINE('|   Borrowed: ' || TO_CHAR(v_date_borrowed, 'DD-MON-YYYY') || RPAD(' ', 20) || 'Due: ' || TO_CHAR(v_due_date, 'DD-MON-YYYY') || LPAD('|', 7));
        DBMS_OUTPUT.PUT_LINE('|   Overdue Days: ' || RPAD(v_overdue_days, 4) || LPAD('|', 46));
        DBMS_OUTPUT.PUT_LINE('|   Return Status: ' || CASE WHEN v_count_bookReturned = 0 THEN RPAD('All Books Returned', 30) ELSE RPAD('Partially Returned', 30) END || LPAD('|', 19));
        DBMS_OUTPUT.PUT_LINE('|' || c_separator || '|');
        
        -- Fine Calculation Details
        DBMS_OUTPUT.PUT_LINE('| FINE DETAILS:' || LPAD('|', 53));
        DBMS_OUTPUT.PUT_LINE('|   Fine ID: ' || fineIdExist|| LPAD('|', 46));
        DBMS_OUTPUT.PUT_LINE('|   Original Fine Amount: ' || 'RM ' || RPAD(TO_CHAR(v_fine_amount, 'FM9,999,990.00'), 10) || LPAD('|', 29));
        
        -- Campaign details
        DBMS_OUTPUT.PUT_LINE('|   Campaign Applied: ' || RPAD(v_campaign_name, 44) || LPAD('|', 2));
        DBMS_OUTPUT.PUT_LINE('|   Campaign Period: ' || TO_CHAR(v_campaign_start_date, 'DD-MON-YYYY') || ' to ' || TO_CHAR(v_campaign_end_date, 'DD-MON-YYYY')|| LPAD('|', 21));
        DBMS_OUTPUT.PUT_LINE('|   Discount Type: ' || CASE WHEN v_is_percentage = 1 THEN RPAD('Percentage (' || v_discount_value || '%)', 20) ELSE RPAD('Fixed Amount', 20) END || LPAD('|', 29));
        IF v_max_discount IS NOT NULL AND v_is_percentage = 1 THEN
            DBMS_OUTPUT.PUT_LINE('|   Maximum Discount: RM ' || 
                                 TO_CHAR(v_max_discount, 'FM9,999,990.00') || LPAD('|', 40));
        END IF;
        DBMS_OUTPUT.PUT_LINE('|' || c_separator || '|');

        -- Payment breakdown
        DBMS_OUTPUT.PUT_LINE('| PAYMENT DETAILS:' || LPAD('|', 50));
        DBMS_OUTPUT.PUT_LINE('|  Payment Methods: ' || RPAD(paymentMethod, 20) ||LPAD('|', 28));
        DBMS_OUTPUT.PUT_LINE('|  Original Fine Amount: RM ' || LPAD(TO_CHAR(NVL(v_fine_amount, 0), 'FM9,999,990.00'), 10) ||LPAD('|', 30));
        DBMS_OUTPUT.PUT_LINE('|  Discount Applied    : RM ' || LPAD(TO_CHAR(NVL(v_discount_applied, 0), 'FM9,999,990.00'), 10) ||LPAD('|', 30));
        v_final_amount := v_fine_amount - v_discount_applied;
        DBMS_OUTPUT.PUT_LINE('|  Final Amount to Pay : RM ' || LPAD(TO_CHAR(NVL(v_final_amount, 0), 'FM9,999,990.00'), 10) ||LPAD('|', 30));
        DBMS_OUTPUT.PUT_LINE('|  Admin Fee           : RM ' || LPAD(TO_CHAR(NVL(v_adminFee, 0), 'FM9,999,990.00'), 10) ||LPAD('|', 30));
        DBMS_OUTPUT.PUT_LINE('|  SST                 : RM ' || LPAD(TO_CHAR(NVL(v_sst, 0), 'FM9,999,990.00'), 10) ||LPAD('|', 30));
        DBMS_OUTPUT.PUT_LINE('|  GRAND TOTAL         : RM ' || LPAD(TO_CHAR(NVL(v_final_amount + v_adminFee + v_sst, 0), 'FM9,999,990.00'), 10) ||LPAD('|', 30));
        DBMS_OUTPUT.PUT_LINE('|' || c_header_separator || '|');
        DBMS_OUTPUT.PUT_LINE('| ' || center_text('Thank you for using the library!', c_width) || LPAD('|', 0.3*c_width+2));
        DBMS_OUTPUT.PUT_LINE('|' || c_separator || '|');
        -- Footer notes
        DBMS_OUTPUT.PUT_LINE('| ' || center_text('Thank you for your payment', c_width) || LPAD('|', 0.4*c_width-1));
        DBMS_OUTPUT.PUT_LINE('| ' || center_text('Keep this receipt for your records', c_width) || LPAD('|', 0.3*c_width+1));
        DBMS_OUTPUT.PUT_LINE('|' || c_header_separator || '|');
        DBMS_OUTPUT.PUT_LINE('| ' || center_text('STATUS: PAYMENT SUCCESSFULLY PROCESSED', c_width) || LPAD('|', 0.3*c_width-1));
        DBMS_OUTPUT.PUT_LINE('|' || c_header_separator || '|');
    END print_receipt;
    
BEGIN
    -- Update the fine record
    v_debug_step := 'Updating fine record';
    global_vars_pkg.set_is_processing(TRUE);
    UPDATE Fine
    SET voucherId = voucherIdApply
    WHERE fineId = fineIdExist;

    v_debug_step := 'Starting procedure';
    DBMS_OUTPUT.PUT_LINE('Starting procedure for fine: ' || fineIdExist || ' and campaign: ' || voucherIdApply);
    
    -- Get campaign and fine details
    v_debug_step := 'Getting campaign details';
    get_campaign_details;
    
    v_debug_step := 'Getting fine details';
    get_fine_details;

    v_debug_step := 'Checking for existing payment methods';
    validate_payment_method(paymentMethod);
    
    -- Calculate discount
    v_debug_step := 'Calculating discount';
    calculate_discount;
    
    UPDATE Fine
    SET discountApplied = v_discount_applied,
        paymentDate = CURRENT_DATE,
            status = 'Paid'
    WHERE fineId = fineIdExist;

    -- Find the total amount
    SELECT finalAmount INTO v_final_amount
    FROM fine
    WHERE fineId = fineIdExist;

    -- Generate transaction and invoice IDs
    v_debug_step := 'Generating transaction IDs';
    generate_transaction_ids;

    -- Create transaction and invoice records
    v_debug_step := 'Creating transaction record';
    INSERT INTO Transaction (
        transactionId, fineId, transactionDate, transactionMethod, amount
    ) VALUES (
        v_transaction_id, fineIdExist, CURRENT_DATE, paymentMethod,  NVL(v_final_amount,0)
    );
    
    v_debug_step := 'Creating invoice record';
    INSERT INTO Invoice (
        invoiceId, transactionId, invoiceDate, remarks, overdueDays
    ) VALUES (
        v_invoice_id, v_transaction_id, CURRENT_DATE, 'Fine payment processed.', v_overdue_days
    );
    
    -- Update book status
    v_debug_step := 'Updating book status';
    update_book_status;
    
    -- Print receipt
    v_debug_step := 'Printing receipt';
    print_receipt;

    IF global_vars_pkg.get_is_updated = 0 THEN
        COMMIT;
    END IF;
    global_vars_pkg.reset_is_updated;
    global_vars_pkg.set_is_processing(FALSE);
EXCEPTION
    WHEN e_campaign_not_found OR e_fine_not_found OR e_campaign_inactive THEN
        DBMS_OUTPUT.PUT_LINE('Transaction rolled back - validation failed at step: ' || v_debug_step);
        ROLLBACK;
        RAISE;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error at step [' || v_debug_step || ']: ' || SQLERRM);
        ROLLBACK;
        RAISE;
END;
/

-- Execute with validation
BEGIN
    DECLARE
        v_fine_id VARCHAR2(20) := UPPER(TRIM('&fineIdInput'));
        v_voucher_id VARCHAR2(20) := TRIM('&voucherIdInput');
        v_payment_method VARCHAR2(50) := TRIM('&paymentMethodInput');
    BEGIN
        -- Convert empty voucher to NULL
        IF v_voucher_id = '' THEN
            v_voucher_id := NULL;
        END IF;
        
        -- Validate inputs
        IF v_fine_id IS NULL THEN 
            RAISE_APPLICATION_ERROR(-20001, 'Please enter the fine ID.'); 
        END IF;
        
        IF v_payment_method IS NULL THEN 
            RAISE_APPLICATION_ERROR(-20001, 'Please enter the payment method.'); 
        END IF;
        
        -- Call the procedure
        DBMS_OUTPUT.PUT_LINE('Processing payment for fine ID: ' || v_fine_id);
        IF v_voucher_id IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('Applying voucher: ' || v_voucher_id);
        END IF;
        
        ApplyVoucher(
            fineIdExist => v_fine_id,
            voucherIdApply => v_voucher_id,
            paymentMethod => v_payment_method
        );
        
        DBMS_OUTPUT.PUT_LINE('Payment processed successfully');
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('Payment processing failed for fine ID: ' || v_fine_id);
    END;
END;
/