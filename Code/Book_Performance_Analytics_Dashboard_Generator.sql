-- Reset any previous formatting
SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF

-- Drop procedure before create to prevent duplicate.
DROP PROCEDURE GenerateBookInsights;

-- Column formatting for the view
SET DEFINE ON
SET SERVEROUTPUT ON
SET LINESIZE 150
SET UNDERLINE OFF
SET VERIFY OFF
SET HEADING OFF
BTITLE CENTER 'Data as of: ' _Date

-- Get user input
ACCEPT isbn CHAR PROMPT 'Enter ISBN: '
ACCEPT startDate DATE PROMPT 'Enter Start Date (DD/MM/YYYY): '
ACCEPT endDate DATE PROMPT 'Enter End Date (DD/MM/YYYY): '

CREATE OR REPLACE PROCEDURE GenerateBookInsights(
    b_BookISBNCode IN CHAR,
    b_startDate IN DATE,
    b_endDate IN DATE
) AS
      -- Declare variables for validation
    v_isbn_valid BOOLEAN := FALSE;
    v_start_date_valid BOOLEAN := FALSE;
    v_end_date_valid BOOLEAN := FALSE;
    
      -- Variables for book details
    v_book_title VARCHAR2(100);
    v_genres VARCHAR2(500);
    v_current_stock NUMBER;
    v_unit_price NUMBER(5,2);
    v_publisher_name VARCHAR2(50);

    -- Variables for borrowing statistics
    v_total_borrowed NUMBER := 0;
    v_avg_borrowed_daily NUMBER(10,2) := 0;
    v_avg_borrowed_weekly NUMBER(10,2) := 0;
    v_avg_borrowed_monthly NUMBER(10,2) := 0;
    v_growth_rate NUMBER(10,2) := 0;
    
    -- Advanced analysis variables
    v_peak_borrow_date DATE;
    v_peak_borrow_count NUMBER := 0;
    v_slow_borrow_date DATE;
    v_slow_borrow_count NUMBER := 999999;
    v_seasonal_pattern VARCHAR2(100) := 'No clear pattern';
    v_reader_segment VARCHAR2(100);

    -- Variables for feedback
    v_avg_rating NUMBER(10,2) := 0;
    v_total_reviews NUMBER := 0;
    v_positive_reviews NUMBER := 0;
    v_neutral_reviews NUMBER := 0;
    v_negative_reviews NUMBER := 0;

    -- Variables for damage/loss
    v_books_broken NUMBER := 0;
    v_books_lost NUMBER := 0;
    v_books_not_returned NUMBER := 0;
    v_damage_rate NUMBER(10,2) := 0;

    -- Variables for date range calculation
    v_days_in_period NUMBER;
    v_weeks_in_period NUMBER;
    v_months_in_period NUMBER;

    -- Stock status and trend indicators
    v_stock_status VARCHAR2(20);
    v_inventory_trend VARCHAR2(20);
    v_financial_impact NUMBER(10,2) := 0;
    
    -- Analysis threshold variables
    v_threshold_low NUMBER := 3;
    v_threshold_high NUMBER := 10;

    -- Color codes for terminal (if supported)
    v_reset VARCHAR2(10) := CHR(27) || '[0m';
    v_red VARCHAR2(10) := CHR(27) || '[31m';
    v_green VARCHAR2(10) := CHR(27) || '[32m';
    v_yellow VARCHAR2(10) := CHR(27) || '[33m';
    v_blue VARCHAR2(10) := CHR(27) || '[34m';
    v_bold VARCHAR2(10) := CHR(27) || '[1m';
BEGIN

   
    -- Calculate time periods
    v_days_in_period := b_endDate - b_startDate + 1;
    v_weeks_in_period := ROUND(v_days_in_period / 7, 2);
    v_months_in_period := MONTHS_BETWEEN(b_endDate, b_startDate);

    -- Get basic book information
    SELECT 
        b.title, 
        bc.availableCopies AS numberOfCopies, 
        b.price,
        p.publisherName,
        LISTAGG(DISTINCT(g.genreName), ', ') WITHIN GROUP (ORDER BY g.genreName) AS genres
    INTO v_book_title, v_current_stock, v_unit_price, v_publisher_name, v_genres
    FROM Book b
    JOIN ISBN i ON b.bookId = i.bookId
    JOIN Publisher p ON i.publisherId = p.publisherId
    LEFT JOIN (
        SELECT bookId, COUNT(*) AS availableCopies
        FROM BookOfCopies
        WHERE status = 'Available'
        GROUP BY bookId
    ) bc ON b.bookId = bc.bookId
    LEFT JOIN BookGenre bg ON b.bookId = bg.bookId
    LEFT JOIN Genre g ON bg.genreId = g.genreId
    WHERE i.isbnId = b_BookISBNCode
    GROUP BY b.title, bc.availableCopies, b.price, p.publisherName;

    -- Get borrowing statistics
    SELECT COUNT(*)
    INTO v_total_borrowed
    FROM Borrowing br
    JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
    JOIN BookOfCopies bc ON bc.copyId = bb.copyId
    JOIN Book b ON b.bookId = bc.bookId
    JOIN ISBN i ON b.bookId = i.bookId
    WHERE i.isbnId = b_BookISBNCode
      AND br.dateBorrow BETWEEN b_startDate AND b_endDate;

    -- Calculate averages
    v_avg_borrowed_daily := v_total_borrowed / v_days_in_period;
    v_avg_borrowed_weekly := v_total_borrowed / v_weeks_in_period;
    v_avg_borrowed_monthly := v_total_borrowed / v_months_in_period;

    -- Get growth rate (compared to previous period of same length)
    SELECT
        CASE
            WHEN COUNT(*) = 0 THEN 0
            ELSE ((v_total_borrowed - COUNT(*)) / COUNT(*)) * 100
        END
    INTO v_growth_rate
    FROM Borrowing br
    JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
    JOIN BookOfCopies bc ON bb.copyId = bc.copyId
    JOIN Book b ON bc.bookId = b.bookId
    JOIN ISBN i ON b.bookId = i.bookId
    WHERE i.isbnId = b_BookISBNCode
      AND br.dateBorrow BETWEEN (b_startDate - v_days_in_period) AND (b_startDate - 1);

    -- Find peak borrowing date (might fail if no data, hence exception block)
    BEGIN
        SELECT borrow_date, borrow_count 
        INTO v_peak_borrow_date, v_peak_borrow_count
        FROM (
            SELECT TRUNC(br.dateBorrow) AS borrow_date, COUNT(*) AS borrow_count
            FROM Borrowing br
            JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
            JOIN BookOfCopies bc ON bc.copyId = bb.copyId
            JOIN Book b ON b.bookId = bc.bookId
            JOIN ISBN i ON b.bookId = i.bookId
            WHERE i.isbnId = b_BookISBNCode
              AND br.dateBorrow BETWEEN b_startDate AND b_endDate
            GROUP BY TRUNC(br.dateBorrow)
            ORDER BY COUNT(*) DESC
        ) WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_peak_borrow_date := NULL;
            v_peak_borrow_count := 0;
    END;
    
    -- Find slowest borrowing date (might fail if no data, hence exception block)
    BEGIN
        SELECT borrow_date, borrow_count 
        INTO v_slow_borrow_date, v_slow_borrow_count
        FROM (
            SELECT TRUNC(br.dateBorrow) AS borrow_date, COUNT(*) AS borrow_count
            FROM Borrowing br
            JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
            JOIN BookOfCopies bc ON bc.copyId = bb.copyId
            JOIN Book b ON b.bookId = bc.bookId
            JOIN ISBN i ON b.bookId = i.bookId
            WHERE i.isbnId = b_BookISBNCode
              AND br.dateBorrow BETWEEN b_startDate AND b_endDate
            GROUP BY TRUNC(br.dateBorrow)
            ORDER BY COUNT(*) ASC
        ) WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_slow_borrow_date := NULL;
            v_slow_borrow_count := 0;
    END;
    
    -- Determine seasonal pattern (simple analysis based on month patterns)
    BEGIN
        WITH monthly_data AS (
            SELECT 
                TO_CHAR(br.dateBorrow, 'MON') as month_name, 
                COUNT(*) as borrow_count
            FROM Borrowing br
            JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
            JOIN BookOfCopies bc ON bc.copyId = bb.copyId
            JOIN Book b ON b.bookId = bc.bookId
            JOIN ISBN i ON b.bookId = i.bookId
            WHERE i.isbnId = b_BookISBNCode
              AND br.dateBorrow BETWEEN b_startDate AND b_endDate
            GROUP BY TO_CHAR(br.dateBorrow, 'MON')
            ORDER BY COUNT(*) DESC
        )
        SELECT 
            CASE 
                WHEN COUNT(*) > 0 THEN
                    'Higher in: ' || LISTAGG(month_name, ', ') WITHIN GROUP (ORDER BY borrow_count DESC)
                ELSE
                    'No clear pattern'
            END
        INTO v_seasonal_pattern
        FROM (SELECT * FROM monthly_data WHERE ROWNUM <= 2);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_seasonal_pattern := 'Insufficient data';
    END;
    
    -- Get feedback statistics with sentiment breakdown
    SELECT 
        AVG(f.rating), 
        COUNT(f.feedbackId),
        SUM(CASE WHEN f.rating >= 4 THEN 1 ELSE 0 END),
        SUM(CASE WHEN f.rating = 3 THEN 1 ELSE 0 END),
        SUM(CASE WHEN f.rating < 3 THEN 1 ELSE 0 END)
    INTO 
        v_avg_rating, 
        v_total_reviews,
        v_positive_reviews,
        v_neutral_reviews,
        v_negative_reviews
    FROM Feedback f
    JOIN Book b ON f.bookId = b.bookId
    JOIN ISBN i ON b.bookId = i.bookId
    WHERE i.isbnId = b_BookISBNCode
      AND f.feedbackDate BETWEEN b_startDate AND b_endDate;

    -- Get broken books 
    SELECT COUNT(*)
    INTO v_books_broken
    FROM Fine f
    JOIN Borrowing br ON f.borrowId = br.borrowId
    JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
    JOIN BookOfCopies bc ON bc.copyId = bb.copyId
    JOIN Book b ON bc.bookId = b.bookId
    JOIN ISBN i ON b.bookId = i.bookId
    WHERE i.isbnId = b_BookISBNCode
      AND bc.status = 'Broken';

    -- Get books lost 
    SELECT COUNT(*)
    INTO v_books_lost
    FROM Fine f
    JOIN Borrowing br ON f.borrowId = br.borrowId
    JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
    JOIN BookOfCopies bc ON bc.copyId = bb.copyId
    JOIN Book b ON bc.bookId = b.bookId
    JOIN ISBN i ON b.bookId = i.bookId
    WHERE i.isbnId = b_BookISBNCode
      AND bc.status = 'Lost';

    -- Get the number of not returned books
    SELECT COUNT(*)
    INTO v_books_not_returned
    FROM Borrowing br
    JOIN BorrowingBooks bb ON br.borrowId = bb.borrowId
    JOIN BookOfCopies bc ON bc.copyId = bb.copyId
    JOIN Book b ON bc.bookId = b.bookId
    JOIN ISBN i ON b.bookId = i.bookId
    WHERE i.isbnId = b_BookISBNCode
      AND br.dateBorrow BETWEEN b_startDate AND b_endDate
      AND bb.dateReturn IS NULL;
      
    -- Calculate damage rate and financial impact
    IF v_total_borrowed > 0 THEN
        v_damage_rate := ((v_books_broken + v_books_lost) / v_total_borrowed) * 100;
    END IF;
    
    v_financial_impact := (v_books_broken + v_books_lost) * v_unit_price;

    -- Determine stock status
    IF v_current_stock = 0 THEN
        v_stock_status := 'Out of Stock';
    ELSIF v_current_stock < 3 THEN
        v_stock_status := 'Low Stock';
    ELSIF v_avg_borrowed_monthly > v_current_stock THEN
        v_stock_status := 'High Demand';
    ELSE
        v_stock_status := 'In Stock';
    END IF;
    
    -- Determine reader segment based on borrow rate and reviews
    IF v_total_borrowed = 0 THEN
        v_reader_segment := 'Inactive';
    ELSIF v_growth_rate > 20 AND v_avg_rating >= 4 THEN
        v_reader_segment := 'Trending and Popular';
    ELSIF v_growth_rate > 10 THEN
        v_reader_segment := 'Growing Interest';
    ELSIF v_avg_borrowed_monthly > v_threshold_high THEN
        v_reader_segment := 'Steady Performer';
    ELSIF v_avg_borrowed_monthly < v_threshold_low THEN
        v_reader_segment := 'Low Demand';
    ELSE
        v_reader_segment := 'Average Performer';
    END IF;
    
    -- Determine inventory trend
    IF v_current_stock = 0 THEN
        v_inventory_trend := 'Critical';
    ELSIF v_growth_rate > 15 AND v_current_stock < v_avg_borrowed_monthly * 1.5 THEN
        v_inventory_trend := 'At Risk';
    ELSIF v_growth_rate < -15 AND v_current_stock > v_avg_borrowed_monthly * 3 THEN
        v_inventory_trend := 'Overstocked';
    ELSIF v_current_stock < v_avg_borrowed_monthly THEN
        v_inventory_trend := 'Under Pressure';
    ELSE
        v_inventory_trend := 'Balanced';
    END IF;

    -- Display enhanced output with advanced analytics - CENTERED FOR LINESIZE 150
    -- DBMS_OUTPUT.PUT_LINE(LPAD('+------------------------------------------------------------+', 200, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('+-----------------------------------------------------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|                   ADVANCED BOOK ANALYTICS DASHBOARD                   |', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('+-----------------------------------------------------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('BOOK: ' || v_bold || v_book_title || v_reset || ' (ISBN: ' || b_BookISBNCode || ')', 75, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('PERIOD: ' || TO_CHAR(b_startDate, 'DD/MM/YYYY') || ' to ' || TO_CHAR(b_endDate, 'DD/MM/YYYY'), 75, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('  Publisher: ' || v_publisher_name, 75, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('  Genres: ' || NVL(v_genres, 'None specified'), 75, ' '));
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Performance snapshot using a simple ASCII progress bar to represent key metrics visually
    DBMS_OUTPUT.PUT_LINE(LPAD('+--------------------------[ PERFORMANCE SNAPSHOT ]------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|  ' || RPAD('Book Usage:', 15) || 
        CASE 
            WHEN v_total_borrowed = 0 THEN '|' || RPAD(' ', 20) || '| 0%' 
            WHEN v_avg_borrowed_monthly/v_total_borrowed > 1 THEN '|' || RPAD('=', 20) || '| 100%'
            ELSE '|' || RPAD('=', ROUND((v_avg_borrowed_monthly/v_total_borrowed)*20)) || 
                 RPAD(' ', 20-ROUND((v_avg_borrowed_monthly/v_total_borrowed)*20)) || '| ' || 
                 TO_CHAR(ROUND((v_avg_borrowed_monthly/v_total_borrowed)*100)) || '%'
        END || ' of used' || LPAD('|', 25), 100, ' '));
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|  ' || RPAD('Growth Rate:', 15) || 
        CASE
            WHEN v_growth_rate > 50 THEN v_green || RPAD('+' || TO_CHAR(ROUND(v_growth_rate), 'FM990.00') || '%',25) || v_reset || RPAD(' Exceptional growth', 39)
            WHEN v_growth_rate > 10 THEN v_green || RPAD('+' || TO_CHAR(ROUND(v_growth_rate), 'FM990.00') || '%', 17) || v_reset || RPAD(' Positive trend', 39)
            WHEN v_growth_rate BETWEEN -10 AND 10 THEN RPAD(TO_CHAR(ROUND(v_growth_rate), 'FM990.00') || '%', 23) || RPAD('Stable',34)
            WHEN v_growth_rate < -10 THEN v_red || RPAD(TO_CHAR(ROUND(v_growth_rate), 'FM990.00') || '%', 17) || v_reset || RPAD(' Declining interest', 39)
        END || '|', 95, ' '));

    DBMS_OUTPUT.PUT_LINE(LPAD('|  ' || RPAD('Satisfaction:', 15) || 
        CASE
            WHEN v_total_reviews = 0 THEN RPAD('No reviews', 57)
            ELSE TO_CHAR(ROUND(v_avg_rating, 1), 'FM9.0') || '/5 [' || 
                 RPAD('*', ROUND(v_avg_rating), '*') || 
                 RPAD('-', 5-ROUND(v_avg_rating), '-') || ']'|| RPAD(' ', 10) || RPAD('(' || 
                 v_total_reviews || ' reviews)', 34)
        END || '|', 95, ' '));
        
    DBMS_OUTPUT.PUT_LINE(LPAD('|  ' || RPAD('Segment:', 15) || 
        CASE 
            WHEN v_reader_segment = 'Trending and Popular' THEN v_bold || v_green || RPAD(v_reader_segment, 60) || v_reset
            WHEN v_reader_segment = 'Growing Interest' THEN v_green || RPAD(v_reader_segment, 60) || v_reset
            WHEN v_reader_segment = 'Low Demand' THEN v_red || RPAD(v_reader_segment, 60) || v_reset
            WHEN v_reader_segment = 'Inactive' THEN v_red || v_bold || RPAD(v_reader_segment, 56) || v_reset
            ELSE RPAD(v_reader_segment, 55)
        END || '|', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('+--------------------------------------------------------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Inventory and Stock Health
    DBMS_OUTPUT.PUT_LINE(LPAD('+------------------------[ INVENTORY INTELLIGENCE ]------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|  Current Stock:     ' || RPAD(v_current_stock || ' copies', 20) || 
        CASE 
            WHEN v_current_stock = 0 THEN v_red || v_bold || RPAD('✘ CRITICAL - REORDER IMMEDIATELY', 36) || v_reset
            WHEN v_current_stock < 3 THEN v_red || RPAD('! LOW - Order more copies soon', 36) || v_reset
            WHEN v_current_stock > v_avg_borrowed_monthly * 3 THEN v_yellow || RPAD('! POSSIBLE OVERSTOCK', 36) || v_reset
            ELSE v_green || RPAD('ADEQUATE', 36) || v_reset
        END || '|', 95, ' '));
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|  Status:            ' || RPAD(v_stock_status, 20) || 
        CASE 
            WHEN v_inventory_trend = 'Critical' THEN v_red || v_bold || '✘ ' || RPAD(v_inventory_trend, 36) || v_reset
            WHEN v_inventory_trend = 'At Risk' THEN v_red || '! ' || RPAD(v_inventory_trend, 36) || v_reset 
            WHEN v_inventory_trend = 'Under Pressure' THEN v_yellow || '! ' || RPAD(v_inventory_trend, 36) || v_reset
            WHEN v_inventory_trend = 'Overstocked' THEN v_yellow || '! ' || RPAD(v_inventory_trend, 36) || v_reset
            ELSE v_green || RPAD(v_inventory_trend, 36) || v_reset
        END || '|', 95, ' '));
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|  Unreturned Books:  ' || RPAD(v_books_not_returned || ' copies', 20) || 
        CASE 
            WHEN v_books_not_returned = 0 THEN v_green || RPAD('ALL RETURNED', 36) || v_reset
            WHEN v_books_not_returned > 3 THEN v_red || RPAD('! FOLLOW UP NEEDED', 36) || v_reset
            ELSE v_yellow || RPAD('! MONITOR SITUATION', 36) || v_reset
        END || '|', 95, ' '));
        
    DBMS_OUTPUT.PUT_LINE(LPAD('|  Damage Rate:       ' || RPAD(TO_CHAR(ROUND(v_damage_rate, 1), 'FM990.0') || '%', 20) || 
        CASE 
            WHEN v_damage_rate = 0 THEN v_green || RPAD('EXCELLENT', 36) || v_reset
            WHEN v_damage_rate > 10 THEN v_red || RPAD('! HIGH DAMAGE RATE', 36) || v_reset
            WHEN v_damage_rate > 5 THEN v_yellow || RPAD('! ABOVE AVERAGE DAMAGE', 36) || v_reset
            ELSE v_green || RPAD('ACCEPTABLE', 36) || v_reset
        END || '|', 95, ' '));
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|  Financial Impact:  ' || RPAD('RM ' || TO_CHAR(v_financial_impact, 'FM999,990.00'), 20) || 
        CASE 
            WHEN v_financial_impact = 0 THEN v_green || RPAD('NO LOSSES', 36) || v_reset
            WHEN v_financial_impact > 100 THEN v_red || RPAD('! SIGNIFICANT LOSSES', 36) || v_reset
            ELSE v_yellow || RPAD('! MONITOR EXPENSES', 36) || v_reset
        END || '|', 95, ' '));
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('+--------------------------------------------------------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Borrowing and Feedback analysis
    DBMS_OUTPUT.PUT_LINE(LPAD('+----------------------[ ADVANCED USAGE ANALYTICS ]------------------------+', 100, ' '));
    -- Pattern analysis
    DBMS_OUTPUT.PUT_LINE(LPAD('| BORROWING PATTERNS                                                       |', 100, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|   Peak Borrowing:   ' || 
        CASE 
            WHEN v_peak_borrow_date IS NULL THEN RPAD('No data available', 53)
            ELSE TO_CHAR(v_peak_borrow_date, 'DD/MM/YYYY') || RPAD(' (' || v_peak_borrow_count || ' borrows)',43)
        END, 100, ' ') || '|');
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|   Slowest Date:     ' || 
        CASE 
            WHEN v_slow_borrow_date IS NULL THEN RPAD('No data available', 53)
            ELSE TO_CHAR(v_slow_borrow_date, 'DD/MM/YYYY') ||  RPAD(' (' || v_slow_borrow_count || ' borrows)', 43)
        END, 92, ' ') || '|');
    
    DBMS_OUTPUT.PUT_LINE('|   Seasonal Pattern: ' || RPAD(v_seasonal_pattern, 53) || '|');
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 100, ' '));
    
    -- Feedback breakdown
    DBMS_OUTPUT.PUT_LINE(LPAD('| FEEDBACK ANALYSIS                                                        |', 100, ' '));
          
    -- Only show if we have reviews
    IF v_total_reviews > 0 THEN
        -- Calculate percentages
        DECLARE
            v_pos_pct NUMBER := ROUND((v_positive_reviews / v_total_reviews) * 100);
            v_neu_pct NUMBER := ROUND((v_neutral_reviews / v_total_reviews) * 100);
            v_neg_pct NUMBER := ROUND((v_negative_reviews / v_total_reviews) * 100);
        BEGIN
            DBMS_OUTPUT.PUT_LINE(LPAD('|   Positive Reviews: ' || RPAD(v_positive_reviews || ' (' || v_pos_pct || '%)', 20) || 
                CASE
                    WHEN v_pos_pct >= 80 THEN v_green || RPAD('***** EXCEPTIONAL', 36) || v_reset
                    WHEN v_pos_pct >= 60 THEN v_green || RPAD('****- VERY GOOD', 36) || v_reset
                    WHEN v_pos_pct >= 40 THEN v_yellow || RPAD('***-- GOOD', 36) || v_reset
                    WHEN v_pos_pct >= 20 THEN v_yellow || RPAD('**--- FAIR', 36) || v_reset
                    ELSE v_red || RPAD('*---- POOR', 36) || v_reset
                END, 100, ' ') || '|');
                
            DBMS_OUTPUT.PUT_LINE(LPAD('|   Neutral Reviews:  ' || v_neutral_reviews || RPAD(' (' || v_neu_pct || '%)', 52), 100, ' ') || '|');
            DBMS_OUTPUT.PUT_LINE(LPAD('|   Negative Reviews: ' || v_negative_reviews || RPAD(' (' || v_neg_pct || '%)', 52), 100, ' ') || '|');
        END;
    ELSE
        DBMS_OUTPUT.PUT_LINE(LPAD('|   No feedback data available in the selected period.                     ', 100, ' ') || '|');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 95, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('+--------------------------------------------------------------------------+', 95, ' '));
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Manager recommendations 
    DBMS_OUTPUT.PUT_LINE(LPAD('+----------------------[ MANAGEMENT RECOMMENDATIONS ]----------------------+', 91, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 91, ' '));
    
    -- Inventory recommendations
    IF v_current_stock = 0 THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_red || v_bold || RPAD('! CRITICAL ACTION: Order ' || 
            CEIL(v_avg_borrowed_monthly * 2) || ' copies immediately', 76) || v_reset, 100, ' ') || '|');
    ELSIF v_current_stock < v_avg_borrowed_monthly THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_red || RPAD('! URGENT: Increase inventory by ' || 
            CEIL(v_avg_borrowed_monthly - v_current_stock + 2) || ' copies', 76) || v_reset, 100, ' ') || '|');
    ELSIF v_current_stock > v_avg_borrowed_monthly * 4 AND v_avg_borrowed_monthly > 0 THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_yellow || RPAD('! Consider redistributing ' || 
            CEIL(v_current_stock - (v_avg_borrowed_monthly * 3)) || ' copies to other branches', 76) || v_reset, 100, ' ') || '|');
    ELSIF v_growth_rate > 20 THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_green || RPAD('Plan for increased demand: Stock ' || 
            CEIL(v_avg_borrowed_monthly * 1.5) || ' total copies', 76) || v_reset, 100, ' ') || '|');
    ELSE
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_green || RPAD('Current inventory levels appear adequate', 76) || v_reset, 100, ' ') || '|');
    END IF;
    
    -- Marketing recommendations based on patterns
    IF v_reader_segment = 'Trending and Popular' THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_green || RPAD('PROMOTION: Feature in "Most Popular" section on website and displays', 73) || v_reset, 100, ' ') || '|');
    ELSIF v_reader_segment = 'Growing Interest' THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_green || RPAD('PROMOTION: Include in "Rising Picks" newsletter', 76) || v_reset, 100, ' ') || '|');
    ELSIF v_reader_segment = 'Low Demand' THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_yellow || RPAD('PROMOTION: Consider bundling with popular titles for increased visibility', 73) || v_reset, 100  , ' ') || '|');
    ELSIF v_reader_segment = 'Inactive' THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_red || RPAD('REVIEW: Evaluate continued stocking based on acquisition cost', 76) || v_reset, 100, ' ') || '|');
    ELSE
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_blue || RPAD('PROMOTION: Include in regular category promotions', 76) || v_reset, 100, ' ') || '|');
    END IF;
    
    -- Placement recommendations based on seasonal patterns
    IF v_seasonal_pattern NOT IN ('No clear pattern', 'Insufficient data') THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_blue || RPAD('SEASONAL: Increase visibility during ' || 
            REGEXP_REPLACE(v_seasonal_pattern, 'Higher in: ', ''), 76) || v_reset, 100, ' ') || '|');
    END IF;
    
    -- Feedback-based recommendations
    IF v_total_reviews > 0 THEN
        IF v_negative_reviews > v_positive_reviews THEN
            DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_red || RPAD('! FEEDBACK: Address negative reviews - consider staff review', 76) || v_reset, 100, ' ') || '|');
        ELSIF v_avg_rating >= 4 THEN
            DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_green || RPAD('FEEDBACK: Highlight positive reviews in promotional materials', 76) || v_reset, 100, ' ') || '|');
        END IF;
    ELSE
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_yellow || RPAD('FEEDBACK: Encourage readers to leave reviews', 76) || v_reset, 100, ' ') || '|');
    END IF;
    
    -- Damage mitigation if needed
    IF v_damage_rate > 10 THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_red || RPAD('! MAINTENANCE: Investigate high damage rate - consider binding check', 76) || v_reset, 100, ' ') || '|');
    END IF;
    
    -- Unreturned books follow-up
    IF v_books_not_returned > 3 THEN
        DBMS_OUTPUT.PUT_LINE(LPAD('| ' || v_red || RPAD('! RECOVERY: Send targeted reminders for unreturned copies', 76) || v_reset, 100, ' ') || '|');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE(LPAD('|                                                                          |', 91, ' '));
    DBMS_OUTPUT.PUT_LINE(LPAD('+--------------------------------------------------------------------------+', 91, ' '));
    
    -- End message with report generation timestamp
    DBMS_OUTPUT.PUT_LINE('');        
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Book with ISBN ' || b_BookISBNCode || ' not found in database.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END GenerateBookInsights;
/


-- Execute with user input
BEGIN
    GenerateBookInsights(
        '&isbn',
        TO_DATE('&startDate', 'DD/MM/YYYY'),
        TO_DATE('&endDate', 'DD/MM/YYYY')
    );
END;
/
SET VERIFY ON