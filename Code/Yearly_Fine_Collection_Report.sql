-- Reset any previous formatting
SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF

SET PAGESIZE 150
SET LINESIZE 210
SET SERVEROUTPUT ON;
SET TRIMSPOOL ON;
SET VERIFY OFF;
SET DEFINE ON;

-- Clear any existing variables
UNDEFINE startYearInput
UNDEFINE endYearInput

ACCEPT startYearInput CHAR PROMPT 'Enter the start year (YYYY) > '
ACCEPT endYearInput   CHAR PROMPT 'Enter the end year (YYYY) > '
CREATE OR REPLACE PROCEDURE YearlyFineCollectionReport (
    p_start_year IN NUMBER,
    p_end_year   IN NUMBER
)
IS
    -- Exception declarations
    e_invalid_years EXCEPTION;
    e_invalid_year_range EXCEPTION;

    -- Cursor to loop through years
    CURSOR cur_years IS
        SELECT LEVEL + p_start_year - 1 AS report_year
        FROM dual
        CONNECT BY LEVEL <= (p_end_year - p_start_year + 1)
        ORDER BY LEVEL;

    -- Modified cursor to get quarterly fine collection with percentage
    -- Now retrieving fineAmount from Fine table directly for each quarter
    CURSOR cur_quarter_fines(p_year NUMBER, p_quarter NUMBER) IS
    WITH yearly_total AS (
        SELECT SUM(f.fineAmount) AS total_year_amount
        FROM Fine f
        WHERE EXTRACT(YEAR FROM f.paymentDate) = p_year
    ),
    quarterly_data AS (
        SELECT SUM(f.fineAmount) AS total_quarter_amount
        FROM Fine f
        WHERE EXTRACT(YEAR FROM f.paymentDate) = p_year
          AND TO_NUMBER(TO_CHAR(f.paymentDate, 'Q')) = p_quarter
    ),
    quarterly_voucher_discount AS (
        SELECT SUM(discountApplied) AS total_voucher_discount
        FROM Fine
        WHERE voucherId IS NOT NULL
          AND EXTRACT(YEAR FROM paymentDate) = p_year
          AND TO_NUMBER(TO_CHAR(paymentDate, 'Q')) = p_quarter
    )
    SELECT
        NVL(qd.total_quarter_amount, 0) AS total_fine,
        CASE
            WHEN yt.total_year_amount > 0
            THEN (qd.total_quarter_amount / yt.total_year_amount) * 100
            ELSE 0
        END AS percentage,
        NVL(qv.total_voucher_discount, 0) AS total_voucher_discount
    FROM yearly_total yt, quarterly_data qd, quarterly_voucher_discount qv;

    -- Cursor to get yearly growth trend
    -- Using transaction amounts (after discounts)
    CURSOR cur_year_trend(p_year NUMBER) IS
        WITH curr_year AS (
            SELECT NVL(SUM(t.amount), 0) AS total
            FROM Fine f
            JOIN Transaction t ON f.fineId = t.fineId
            WHERE EXTRACT(YEAR FROM t.transactionDate) = p_year
        ),
        prev_year AS (
            SELECT NVL(SUM(t.amount), 0) AS total
            FROM Fine f
            JOIN Transaction t ON f.fineId = t.fineId
            WHERE EXTRACT(YEAR FROM t.transactionDate) = p_year - 1
        )
        SELECT
            CASE
                WHEN pv.total > 0
                THEN ((cy.total - pv.total) / pv.total) * 100
                ELSE 0
            END AS growth_percent
        FROM curr_year cy, prev_year pv;

    -- Cursor to get top vouchers by year
    CURSOR cur_top_vouchers(p_year NUMBER) IS
        WITH yearly_voucher_count AS (
            SELECT COUNT(*) AS total_voucher_count
            FROM Fine
            WHERE EXTRACT(YEAR FROM paymentDate) = p_year
            AND voucherId IS NOT NULL
        )
        SELECT
            v.voucherName,
            COUNT(*) AS usage_count,
            NVL(SUM(f.discountApplied), 0) AS total_discount,
            CASE
                WHEN yvc.total_voucher_count > 0
                THEN (COUNT(*) / yvc.total_voucher_count) * 100
                ELSE 0
            END AS usage_percentage
        FROM Fine f
        JOIN Voucher v ON f.voucherId = v.voucherId
        CROSS JOIN yearly_voucher_count yvc
        WHERE EXTRACT(YEAR FROM f.paymentDate) = p_year
        GROUP BY v.voucherName, yvc.total_voucher_count
        ORDER BY COUNT(*) DESC
        FETCH FIRST 3 ROWS ONLY;

    -- Cursor for yearly summary
    CURSOR cur_yearly_summary IS
        SELECT
            EXTRACT(YEAR FROM t.transactionDate) AS report_year,
            COUNT(*) AS total_fines,
            SUM(t.amount) AS total_amount,
            SUM(CASE WHEN voucherId IS NOT NULL THEN 1 ELSE 0 END) AS voucher_used_count,
            CASE
                WHEN COUNT(*) > 0
                THEN (SUM(CASE WHEN voucherId IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*)) * 100
                ELSE 0
            END AS voucher_usage_percentage
        FROM Fine f
        JOIN  Transaction t ON f.fineId = t.fineId
        WHERE EXTRACT(YEAR FROM t.transactionDate) BETWEEN p_start_year AND p_end_year
        GROUP BY EXTRACT(YEAR FROM t.transactionDate)
        ORDER BY EXTRACT(YEAR FROM t.transactionDate);

    -- Cursor for overall statistics
-- Cursor for overall statistics
CURSOR cur_overall_stats IS
WITH top_voucher AS (
    SELECT 
        v.voucherName AS voucher_name,
        COUNT(*) AS usage_count
    FROM Fine f
    JOIN Transaction t ON f.fineId = t.fineId
    JOIN Voucher v ON f.voucherId = v.voucherId
    WHERE f.voucherId IS NOT NULL
    AND EXTRACT(YEAR FROM t.transactionDate) BETWEEN p_start_year AND p_end_year
    GROUP BY v.voucherName
    ORDER BY COUNT(*) DESC
    FETCH FIRST 1 ROW ONLY
),
overall_stats AS (
    SELECT 
        COUNT(*) AS total_fines,
        SUM(t.amount) AS total_amount,
        ROUND(SUM(t.amount)/COUNT(*), 2) AS avg_fine,
        MIN(t.amount) AS min_fine,
        MAX(t.amount) AS max_fine,
        COUNT(DISTINCT f.voucherId) AS unique_vouchers_used,
        SUM(CASE WHEN f.voucherId IS NOT NULL THEN 1 ELSE 0 END) AS total_vouchers_used,
        CASE
            WHEN COUNT(*) > 0
            THEN (SUM(CASE WHEN f.voucherId IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*)) * 100
            ELSE 0
        END AS voucher_usage_percentage
    FROM Fine f
    JOIN Transaction t ON f.fineId = t.fineId
    WHERE t.fineId IS NOT NULL 
    AND EXTRACT(YEAR FROM t.transactionDate) BETWEEN p_start_year AND p_end_year
)
SELECT 
    o.total_fines,
    o.total_amount,
    o.avg_fine,
    o.min_fine,
    o.max_fine,
    o.unique_vouchers_used,
    o.total_vouchers_used,
    o.voucher_usage_percentage,
    NVL(tv.voucher_name, 'N/A') AS top_voucher_name,
    NVL(tv.usage_count, 0) AS top_voucher_count
FROM overall_stats o
CROSS JOIN top_voucher tv;
    
    -- Local variables
    v_quarterly_fine     NUMBER(12,2);
    v_quarterly_percent  NUMBER(5,1);
    v_quarterly_discount_applied  NUMBER(12,2);
    v_year_trend         NUMBER(8,2);
    v_current_year       NUMBER := EXTRACT(YEAR FROM SYSDATE);
    v_total_fine_amount  NUMBER(12,2) := 0;
    v_total_fine_count   NUMBER := 0;
    v_total_voucher_uses NUMBER := 0;
    v_voucher_percentage NUMBER(5,1);
    v_yearly_total       NUMBER(12,2);
    v_yearly_discount    NUMBER(12,2) := 0;
    v_top_voucher_name VARCHAR2(100);
    v_voucher_count NUMBER(12,2);

    -- Add variables to track quarterly totals across all years
    v_q1_total_fine      NUMBER(12,2) := 0;
    v_q2_total_fine      NUMBER(12,2) := 0;
    v_q3_total_fine      NUMBER(12,2) := 0;
    v_q4_total_fine      NUMBER(12,2) := 0;
    v_q1_total_discount  NUMBER(12,2) := 0;
    v_q2_total_discount  NUMBER(12,2) := 0;
    v_q3_total_discount  NUMBER(12,2) := 0;
    v_q4_total_discount  NUMBER(12,2) := 0;
    v_grand_total        NUMBER(12,2) := 0;
    v_total_discount     NUMBER(12,2) := 0;

    -- For overall statistics
    v_overall_fine_count    NUMBER;
    v_overall_fine_amount   NUMBER(12,2);
    v_overall_avg_fine      NUMBER(12,2);
    v_overall_min_fine      NUMBER(12,2);
    v_overall_max_fine      NUMBER(12,2);
    v_unique_vouchers       NUMBER;
    v_total_voucher_count   NUMBER;
    v_overall_voucher_pct   NUMBER(5,1);

    -- Table formatting variables
    v_line      VARCHAR2(100) := '-';
    v_line_sep  VARCHAR2(100) := '|';
    v_cross     VARCHAR2(100) := '+';

    -- Output column widths
    c_year_width    CONSTANT NUMBER := 14;
    c_quarter_width CONSTANT NUMBER := 32;
    c_yearly_width  CONSTANT NUMBER := 20; -- Width for yearly total column
    c_trends_width  CONSTANT NUMBER := 16;

    -- Table structure constants
    v_top_line      VARCHAR2(1000);
    v_header_line   VARCHAR2(1000);
    v_data_line     VARCHAR2(1000);
    v_bottom_line   VARCHAR2(1000);

    -- Report ID from sequence
    v_report_id         NUMBER;
    PROCEDURE print_footer;
    PROCEDURE print_line(p_char IN CHAR DEFAULT '-', p_cross IN CHAR DEFAULT v_line_sep);

    -- Helper function to format the trend value with color indication
    FUNCTION format_trend(p_value IN NUMBER) RETURN VARCHAR2 IS
        -- ANSI color codes
        v_red     CONSTANT VARCHAR2(10) := CHR(27) || '[31m'; -- Red for negative trends
        v_green   CONSTANT VARCHAR2(10) := CHR(27) || '[32m'; -- Green for positive trends
        v_yellow  CONSTANT VARCHAR2(10) := CHR(27) || '[33m'; -- Yellow for moderate trends
        v_blue    CONSTANT VARCHAR2(10) := CHR(27) || '[34m'; -- Blue for stable trends
        v_reset   CONSTANT VARCHAR2(10) := CHR(27) || '[0m';  -- Reset to default color
        
        v_formatted_trend VARCHAR2(50);
    BEGIN
        IF p_value IS NULL THEN
            RETURN '--';
        ELSIF p_value > 10 THEN
            -- Strong positive trend (dark green)
            v_formatted_trend := v_green || TO_CHAR(p_value, 'FM990.00') || '%' || v_reset;
        ELSIF p_value > 5 THEN
            -- Moderate positive trend (light green)
            v_formatted_trend := v_green || TO_CHAR(p_value, 'FM990.00') || '%' || v_reset;
        ELSIF p_value > 0 THEN
            -- Slight positive trend (yellow-green)
            v_formatted_trend := v_yellow || TO_CHAR(p_value, 'FM990.00') || '%' || v_reset;
        ELSIF p_value = 0 THEN
            -- Stable/neutral (blue)
            v_formatted_trend := v_blue || '0.00%' || v_reset;
        ELSIF p_value > -5 THEN
            -- Slight negative trend (light red)
            v_formatted_trend := v_yellow || TO_CHAR(p_value, 'FM990.00') || '%' || v_reset;
        ELSIF p_value > -10 THEN
            -- Moderate negative trend (medium red)
            v_formatted_trend := v_red || TO_CHAR(p_value, 'FM990.00') || '%' || v_reset;
        ELSE
            -- Strong negative trend (dark red)
            v_formatted_trend := v_red || TO_CHAR(p_value, 'FM990.00') || '%' || v_reset;
        END IF;
        
        RETURN v_formatted_trend;
    END;
    
    -- Print footer
    PROCEDURE print_footer IS
    BEGIN
        print_line('=', v_cross);
        DBMS_OUTPUT.PUT_LINE(v_line_sep || LPAD('Report ID: ' || v_report_id || ' | Generated on: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'), 110, ' ') || LPAD(v_line_sep, 56));
        print_line('=', v_cross);
        DBMS_OUTPUT.PUT_LINE(CHR(10));
    END print_footer;

    -- Print horizontal line
    PROCEDURE print_line(p_char IN CHAR DEFAULT '-', p_cross IN CHAR DEFAULT v_line_sep) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_cross || RPAD(p_char, 165, p_char) || p_cross);
    END print_line;

BEGIN
    SELECT LIBRARY_REPORT_SEQ.NEXTVAL INTO v_report_id FROM DUAL;
    -- Validate input parameters
    IF p_start_year IS NULL OR p_end_year IS NULL THEN
        RAISE e_invalid_years;
    END IF;

    IF p_start_year > p_end_year OR p_start_year < 2000 OR p_end_year > v_current_year + 5 THEN
        RAISE e_invalid_year_range;
    END IF;

    -- Create table border lines
    v_top_line := v_cross || RPAD(v_line, c_year_width, v_line) || v_cross ||
                 RPAD(v_line, c_quarter_width*4.6, v_line) || v_cross ||
                 RPAD(v_line, c_yearly_width, v_line) || v_cross ||
                 RPAD(v_line, c_trends_width, v_line) || v_cross;

    v_header_line := v_cross || RPAD(v_line, c_year_width, v_line) || v_cross ||
                    RPAD(v_line, c_quarter_width+4, v_line) || v_cross ||
                    RPAD(v_line, c_quarter_width+4, v_line) || v_cross ||
                    RPAD(v_line, c_quarter_width+4, v_line) || v_cross ||
                    RPAD(v_line, c_quarter_width+4, v_line) || v_cross ||
                    RPAD(v_line, c_yearly_width, v_line) || v_cross ||
                    RPAD(v_line, c_trends_width, v_line) || v_cross;

    v_bottom_line := v_top_line;

    -- Display the report title
    DBMS_OUTPUT.PUT_LINE(CHR(10) || LPAD('FINE COLLECTION REPORT', 100, ' '));
    DBMS_OUTPUT.PUT_LINE(CHR(10));

    -- Display the table header
    DBMS_OUTPUT.PUT_LINE(v_top_line);
    DBMS_OUTPUT.PUT_LINE(v_line_sep || RPAD(' ', c_year_width) ||
                         v_line_sep || LPAD('Total Collection', 3*c_quarter_width-3, ' ') || RPAD(' ', 1.7*c_quarter_width) ||
                         v_line_sep || LPAD('  Yearly Total    ', c_yearly_width, ' ') ||
                         v_line_sep || RPAD(' ', c_trends_width, ' ') || v_line_sep);
    DBMS_OUTPUT.PUT_LINE(v_line_sep || RPAD(' ', c_year_width, ' ') ||
                         v_line_sep || RPAD('-', c_quarter_width*4.2+5, '-') || RPAD('-', c_quarter_width*0.2+2, '-') || 
                         v_line_sep || RPAD(' ', c_yearly_width, ' ') || 
                         v_line_sep || RPAD(' ', c_trends_width) || v_line_sep);
    DBMS_OUTPUT.PUT_LINE(v_line_sep || LPAD(' Year', 0.6*c_year_width+1, ' ') || RPAD(' ', 0.4*c_year_width-1)  ||
                         v_line_sep || LPAD(' Q1', 0.6*c_quarter_width, ' ') || LPAD(' ', 0.5*c_quarter_width+1) ||
                         v_line_sep || LPAD(' Q2', 0.6*c_quarter_width, ' ') || LPAD(' ', 0.5*c_quarter_width+1) ||
                         v_line_sep || LPAD(' Q3', 0.6*c_quarter_width, ' ') || LPAD(' ', 0.5*c_quarter_width+1) ||
                         v_line_sep || LPAD(' Q4', 0.6*c_quarter_width, ' ') || LPAD(' ', 0.5*c_quarter_width+1) ||
                         v_line_sep || LPAD(' Amount', 0.7*c_yearly_width, ' ') ||
                         LPAD(v_line_sep, 0.3*c_yearly_width+1) || LPAD(' Trends', 0.7*c_trends_width, ' ') || LPAD(v_line_sep, 0.4*c_trends_width));
    DBMS_OUTPUT.PUT_LINE(v_line_sep || RPAD(' ', c_year_width, ' ') || 
                         v_line_sep || RPAD('-', c_quarter_width*4.6, '-') || 
                         v_line_sep || RPAD(' ', c_yearly_width, ' ') || 
                         v_line_sep || RPAD(' ', c_trends_width) || v_line_sep);
    DBMS_OUTPUT.PUT_LINE(v_line_sep || RPAD(' ', c_year_width, ' ') || 
                         v_line_sep || LPAD('Fine Amount',16) || RPAD(' ', 5) || v_line_sep || LPAD('Fine Waived',13) || ' ' ||
                         v_line_sep || LPAD('Fine Amount',16) || RPAD(' ', 5) || v_line_sep || LPAD('Fine Waived',13) || ' ' ||
                         v_line_sep || LPAD('Fine Amount',16) || RPAD(' ', 5) || v_line_sep || LPAD('Fine Waived',13) || ' ' ||
                         v_line_sep || LPAD('Fine Amount',16) || RPAD(' ', 5) || v_line_sep || LPAD('Fine Waived',13) || ' ' || 
                         v_line_sep || RPAD(' ', c_yearly_width) || 
                         v_line_sep || RPAD(' ', c_trends_width) || v_line_sep);
    DBMS_OUTPUT.PUT_LINE(v_header_line);

    -- Process each year and its quarters
    FOR year_rec IN cur_years LOOP
        v_yearly_total := 0;
        v_yearly_discount := 0;

        DBMS_OUTPUT.PUT(v_line_sep || ' ' || RPAD(year_rec.report_year, c_year_width-1, ' ') || v_line_sep);

        -- Process each quarter
        FOR i IN 1..4 LOOP
            -- Get quarterly fine amount and percentage
            OPEN cur_quarter_fines(year_rec.report_year, i);
            FETCH cur_quarter_fines
            INTO v_quarterly_fine, v_quarterly_percent, v_quarterly_discount_applied;
            CLOSE cur_quarter_fines;

            v_yearly_total := v_yearly_total + v_quarterly_fine;
            v_yearly_discount := v_yearly_discount + v_quarterly_discount_applied;
            
            -- Add to quarterly totals across all years
            CASE i
                WHEN 1 THEN
                    v_q1_total_fine := v_q1_total_fine + v_quarterly_fine;
                    v_q1_total_discount := v_q1_total_discount + v_quarterly_discount_applied;
                WHEN 2 THEN
                    v_q2_total_fine := v_q2_total_fine + v_quarterly_fine;
                    v_q2_total_discount := v_q2_total_discount + v_quarterly_discount_applied;
                WHEN 3 THEN
                    v_q3_total_fine := v_q3_total_fine + v_quarterly_fine;
                    v_q3_total_discount := v_q3_total_discount + v_quarterly_discount_applied;
                WHEN 4 THEN
                    v_q4_total_fine := v_q4_total_fine + v_quarterly_fine;
                    v_q4_total_discount := v_q4_total_discount + v_quarterly_discount_applied;
            END CASE;

            -- Format and display the quarterly data
            DBMS_OUTPUT.PUT(' ' ||
                           RPAD('RM '|| LPAD(TO_CHAR(v_quarterly_fine, 'FM999,990.00'), 7) ||
                                LPAD('(' || TO_CHAR(NVL(v_quarterly_percent, 0), 'FM90.00') || '%)', 9),
                                (c_quarter_width/2)+4, ' ') || v_line_sep || '  RM ' || LPAD(TO_CHAR(v_quarterly_discount_applied, 'FM999,990.00') || ' ', 9) ||
                           v_line_sep);
        END LOOP;

        -- Get yearly transaction total (after discounts applied)
        -- We'll use a separate query to get the yearly transaction total
        DECLARE
            v_yearly_transaction_total NUMBER(12,2);
            CURSOR cur_yearly_transaction(p_year NUMBER) IS
                SELECT NVL(SUM(t.amount), 0) AS total_amount
                FROM Transaction t
                WHERE fineId IS NOT NULL AND EXTRACT(YEAR FROM t.transactionDate) = p_year;
        BEGIN
            OPEN cur_yearly_transaction(year_rec.report_year);
            FETCH cur_yearly_transaction INTO v_yearly_transaction_total;
            CLOSE cur_yearly_transaction;
            
            -- Update grand total with transaction amount (after discounts)
            v_grand_total := v_grand_total + v_yearly_transaction_total;
            
            -- Display the yearly total (transaction amount after discounts)
            DBMS_OUTPUT.PUT(' ' || RPAD('RM ' || LPAD(TO_CHAR(v_yearly_transaction_total, 'FM999,990.00'), 10), c_yearly_width-1, ' ') || v_line_sep);
        END;
        
        -- Get the year trend
        IF year_rec.report_year > p_start_year THEN
            OPEN cur_year_trend(year_rec.report_year);
            FETCH cur_year_trend INTO v_year_trend;
            CLOSE cur_year_trend;
        ELSE
            v_year_trend := 0; -- First year has no previous year to compare
        END IF;

        -- Display the trend
        DBMS_OUTPUT.PUT_LINE(' ' || LPAD(format_trend(v_year_trend), 19) || LPAD(v_line_sep, 5));
    END LOOP;
    
    -- Display table footer
    DBMS_OUTPUT.PUT_LINE(v_bottom_line);
    DBMS_OUTPUT.PUT_LINE(v_line_sep || RPAD(' TOTAL', c_year_width) ||
                         v_line_sep || ' ' || RPAD('RM '|| LPAD(TO_CHAR(v_q1_total_fine, 'FM999,990.00'), 9), (c_quarter_width/2)+4, ' ') || 
                         v_line_sep || '  RM ' || LPAD(TO_CHAR(v_q1_total_discount, 'FM999,990.00') || ' ', 9) ||
                         v_line_sep || ' ' || RPAD('RM '|| LPAD(TO_CHAR(v_q2_total_fine, 'FM999,990.00' ), 9), (c_quarter_width/2)+4, ' ') || 
                         v_line_sep || '  RM ' || LPAD(TO_CHAR(v_q2_total_discount, 'FM999,990.00') || ' ', 9) ||
                         v_line_sep || ' ' || RPAD('RM '|| LPAD(TO_CHAR(v_q3_total_fine, 'FM999,990.00'), 9), (c_quarter_width/2)+4, ' ') || 
                         v_line_sep || '  RM ' || LPAD(TO_CHAR(v_q3_total_discount, 'FM999,990.00') || ' ', 9) ||
                         v_line_sep || ' ' || RPAD('RM '|| LPAD(TO_CHAR(v_q4_total_fine, 'FM999,990.00'), 9), (c_quarter_width/2)+4, ' ') || 
                         v_line_sep || '  RM ' || LPAD(TO_CHAR(v_q4_total_discount, 'FM999,990.00') || ' ', 9) ||
                         v_line_sep || RPAD(' RM ' || LPAD(TO_CHAR(v_grand_total, 'FM999,990.00'), 10), c_yearly_width, ' ') || v_line_sep || RPAD(' ', c_trends_width) || v_line_sep);
    DBMS_OUTPUT.PUT_LINE(v_bottom_line);

    -- Get overall statistics
    OPEN cur_overall_stats;
        FETCH cur_overall_stats INTO
            v_overall_fine_count, 
            v_overall_fine_amount, 
            v_overall_avg_fine,
            v_overall_min_fine, 
            v_overall_max_fine, 
            v_unique_vouchers,
            v_total_voucher_count, 
            v_overall_voucher_pct, 
            v_top_voucher_name, 
            v_voucher_count;
        CLOSE cur_overall_stats;

    -- Display summary section
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '==============================');
    DBMS_OUTPUT.PUT_LINE('SUMMARY REPORT');
    DBMS_OUTPUT.PUT_LINE('==============================');
    DBMS_OUTPUT.PUT_LINE('Total Fines Collected: ' || TO_CHAR(v_overall_fine_count));
    DBMS_OUTPUT.PUT_LINE('Total Fine Amount: RM ' || TO_CHAR(v_grand_total, 'FM999,999,990.00'));
    DBMS_OUTPUT.PUT_LINE('Average Fine Amount: RM ' || TO_CHAR(v_overall_avg_fine, 'FM999,990.00'));
    DBMS_OUTPUT.PUT_LINE('Fine Range: RM ' || TO_CHAR(v_overall_min_fine, 'FM999,990.00') ||
                       ' - RM ' || TO_CHAR(v_overall_max_fine, 'FM999,990.00'));
    DBMS_OUTPUT.PUT_LINE('Voucher Usage: ' || TO_CHAR(v_total_voucher_count) ||
                       ' (' || TO_CHAR(v_overall_voucher_pct, 'FM990.0') || '% of all fines)');
    DBMS_OUTPUT.PUT_LINE('Unique Vouchers Used: ' || TO_CHAR(v_unique_vouchers));
    DBMS_OUTPUT.PUT_LINE('- Most Popular Voucher:  ' || NVL(v_top_voucher_name, 'N/A') || ' (used ' || v_voucher_count || ' times)');

    -- Recommendations and insights section
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '==============================');
    DBMS_OUTPUT.PUT_LINE('KEY INSIGHTS AND RECOMMENDATIONS');
    DBMS_OUTPUT.PUT_LINE('==============================');

    -- Determine if there's an increasing or decreasing trend
    IF v_overall_fine_amount > 0 THEN
        -- Check if most recent year is available for trend analysis
        IF v_current_year BETWEEN p_start_year AND p_end_year THEN
            OPEN cur_year_trend(v_current_year);
            FETCH cur_year_trend INTO v_year_trend;
            CLOSE cur_year_trend;

            IF v_year_trend > 5 THEN
                DBMS_OUTPUT.PUT_LINE('* Significant increase of '||TO_CHAR(v_year_trend,'FM990.0')||'% this year.');
            ELSIF v_year_trend < -5 THEN
                DBMS_OUTPUT.PUT_LINE('* Significant decrease of '||TO_CHAR(ABS(v_year_trend),'FM990.0')||'% this year.');
            ELSE
                DBMS_OUTPUT.PUT_LINE('* Collections are stable compared to last year.');
            END IF;
        END IF;

        -- Voucher usage insights
        IF v_overall_voucher_pct > 50 THEN
            DBMS_OUTPUT.PUT_LINE('* High voucher usage ('||TO_CHAR(v_overall_voucher_pct,'FM990.0')||'%) - program is effective.');
        ELSIF v_overall_voucher_pct < 20 THEN
            DBMS_OUTPUT.PUT_LINE('* Low voucher usage ('||TO_CHAR(v_overall_voucher_pct,'FM990.0')||'%) - consider promotion.');
        END IF;

        -- Quarterly performance analysis
        DECLARE
            v_weak_quarter NUMBER;
            v_strong_quarter NUMBER;
            v_min_quarter_amount NUMBER := LEAST(v_q1_total_fine, v_q2_total_fine, v_q3_total_fine, v_q4_total_fine);
            v_max_quarter_amount NUMBER := GREATEST(v_q1_total_fine, v_q2_total_fine, v_q3_total_fine, v_q4_total_fine);
        BEGIN
            -- Identify weakest and strongest quarters
            IF v_q1_total_fine = v_min_quarter_amount THEN
                v_weak_quarter := 1;
            ELSIF v_q2_total_fine = v_min_quarter_amount THEN
                v_weak_quarter := 2;
            ELSIF v_q3_total_fine = v_min_quarter_amount THEN
                v_weak_quarter := 3;
            ELSE
                v_weak_quarter := 4;
            END IF;

            IF v_q1_total_fine = v_max_quarter_amount THEN
                v_strong_quarter := 1;
            ELSIF v_q2_total_fine = v_max_quarter_amount THEN
                v_strong_quarter := 2;
            ELSIF v_q3_total_fine = v_max_quarter_amount THEN
                v_strong_quarter := 3;
            ELSE
                v_strong_quarter := 4;
            END IF;

            -- Provide data-driven quarterly recommendations
            DBMS_OUTPUT.PUT_LINE('* Q'||v_weak_quarter||' had lowest collections (RM'||
                                TO_CHAR(v_min_quarter_amount,'FM999,990.00')||') - review processes.');
            DBMS_OUTPUT.PUT_LINE('* Q'||v_strong_quarter||' performed best (RM'||
                                TO_CHAR(v_max_quarter_amount,'FM999,990.00')||') - replicate strategies.');
        END;

        -- Voucher effectiveness analysis
        IF v_total_voucher_count > 0 THEN
            DBMS_OUTPUT.PUT_LINE('* Top voucher "'||NVL(v_top_voucher_name,'N/A')||'" accounted for '||
                                TO_CHAR((v_voucher_count/v_total_voucher_count)*100,'FM990.0')||'% of voucher usage.');

            -- Check if top voucher dominates usage
            IF (v_voucher_count/v_total_voucher_count) > 0.5 THEN
                DBMS_OUTPUT.PUT_LINE('  - Consider diversifying voucher offerings to reduce reliance on one promotion.');
            END IF;
        END IF;
    ELSE
    DBMS_OUTPUT.PUT_LINE('* No fine collection data available for analysis.');
END IF;

    DBMS_OUTPUT.PUT_LINE(CHR(10));

    print_footer;
    COMMIT;

EXCEPTION
    WHEN e_invalid_years THEN
        DBMS_OUTPUT.PUT_LINE('Error: Start year and end year must not be NULL');
        ROLLBACK;
    WHEN e_invalid_year_range THEN
        DBMS_OUTPUT.PUT_LINE('Error: Invalid year range. Start year must be less than or equal to end year, ' ||
                            'and both must be between 2000 and ' || (v_current_year + 5));
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error Code: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('Error Message: ' || SQLERRM);
        ROLLBACK;
END YearlyFineCollectionReport;
/

-- Execute with validation
BEGIN
  DECLARE
    v_start_year NUMBER;
    v_end_year NUMBER;
    v_current_year NUMBER := EXTRACT(YEAR FROM SYSDATE);
  BEGIN
    -- Validate and convert start year
    BEGIN
      v_start_year := TO_NUMBER('&startYearInput');
      
      -- Check if year is reasonable (1900-current year+5)
      IF v_start_year < 1900 OR v_start_year > v_current_year + 5 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Start year must be between 1900 and ' || (v_current_year + 5));
      END IF;
    EXCEPTION
      WHEN VALUE_ERROR THEN
        RAISE_APPLICATION_ERROR(-20002, 'Start year must be a valid number');
    END;
    
    -- Validate and convert end year
    BEGIN
      v_end_year := TO_NUMBER('&endYearInput');
      
      -- Check if year is reasonable
      IF v_end_year < 1900 OR v_end_year > v_current_year + 5 THEN
        RAISE_APPLICATION_ERROR(-20003, 'End year must be between 1900 and ' || (v_current_year + 5));
      END IF;
    EXCEPTION
      WHEN VALUE_ERROR THEN
        RAISE_APPLICATION_ERROR(-20004, 'End year must be a valid number');
    END;
    
    -- Validate year order
    IF v_start_year > v_end_year THEN
      RAISE_APPLICATION_ERROR(-20005, 'Start year must be less than or equal to end year');
    END IF;
    
    -- Call the procedure with validated inputs
    DBMS_OUTPUT.PUT_LINE('Generating report for ' || v_start_year || ' to ' || v_end_year);
    YearlyFineCollectionReport(
      p_start_year => v_start_year,
      p_end_year => v_end_year
    );
    
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
      DBMS_OUTPUT.PUT_LINE('Report generation failed');
  END;
END;
/

-- Reset any previous formatting
SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF
