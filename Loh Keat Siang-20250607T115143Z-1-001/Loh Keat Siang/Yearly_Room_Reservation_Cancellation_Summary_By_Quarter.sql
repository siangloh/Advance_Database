-- Reset any previous formatting
SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF

-- Drop View before create to prevent duplicate.
DROP VIEW V_VoucherSummary;

-- Column formatting for the view
SET LINESIZE 170
SET PAGESIZE 20
SET UNDERLINE OFF
SET HEADING OFF

-- First, create a view to hold our cancellation data by quarter
CREATE OR REPLACE VIEW V_QuarterlyCancellations AS
SELECT 
    EXTRACT(YEAR FROM rr.reserveDateTime) AS year,
    TO_CHAR(rr.reserveDateTime, 'Q') AS quarter,
    COUNT(*) AS cancellations,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY EXTRACT(YEAR FROM rr.reserveDateTime)), 2) AS percentage_of_yearly_cancellations
FROM 
    RoomReservation rr
JOIN 
    Room r ON rr.roomId = r.roomId
JOIN 
    RoomType rt ON r.roomTypeId = rt.roomTypeId
WHERE 
    rr.status = 'Cancelled'
GROUP BY 
    EXTRACT(YEAR FROM rr.reserveDateTime),
    TO_CHAR(rr.reserveDateTime, 'Q');

TTITLE CENTER 'Yearly Room Reservation Cancellation Summary by Quarter' SKIP 2
SET TERMOUT OFF
COLUMN today NEW_VALUE _DATE
SELECT TO_CHAR(SYSDATE, 'DD/MM/YYYY') AS today FROM dual;
SET TERMOUT ON
BTITLE CENTER 'Data as of: ' _DATE
-- Now put all the data rows into a single query
WITH yearly_data AS (
    SELECT
        year,
        MAX(CASE WHEN quarter = '1' THEN cancellations ELSE 0 END) AS Q1,
        MAX(CASE WHEN quarter = '2' THEN cancellations ELSE 0 END) AS Q2,
        MAX(CASE WHEN quarter = '3' THEN cancellations ELSE 0 END) AS Q3,
        MAX(CASE WHEN quarter = '4' THEN cancellations ELSE 0 END) AS Q4,
        SUM(cancellations) AS yearly_total
    FROM V_QuarterlyCancellations
    GROUP BY year
),
pivot_data AS (
    SELECT
        curr.year,
        curr.Q1, curr.Q2, curr.Q3, curr.Q4,
        curr.yearly_total,
        prev.yearly_total AS last_year_total,
        NVL(ROUND(
            CASE
                WHEN prev.yearly_total = 0 THEN NULL
                ELSE ((curr.yearly_total - prev.yearly_total) * 100.0 / prev.yearly_total)
            END, 2
        ), 0) AS trend_percentage
    FROM yearly_data curr
    LEFT JOIN yearly_data prev ON curr.year = prev.year + 1
),
formatted_rows AS (
    SELECT
        year,
        RPAD(' ',14) || '|' || RPAD('         ' || year, 22, ' ') || '|' ||
        RPAD('     ' || LPAD(TO_CHAR(Q1, 'FM999,999'), 4, ' ') || ' (' || TO_CHAR(ROUND(Q1 * 100.0 / NULLIF(yearly_total, 0), 1), 'FM990.0') || '%)', 20, ' ') || '|' ||
        RPAD('     ' || LPAD(TO_CHAR(Q2, 'FM999,999'), 4, ' ') || ' (' || TO_CHAR(ROUND(Q2 * 100.0 / NULLIF(yearly_total, 0), 1), 'FM990.0') || '%)', 20, ' ') || '|' ||
        RPAD('     ' || LPAD(TO_CHAR(Q3, 'FM999,999'), 4, ' ') || ' (' || TO_CHAR(ROUND(Q3 * 100.0 / NULLIF(yearly_total, 0), 1), 'FM990.0') || '%)', 20, ' ') || '|' ||
        RPAD('     ' || LPAD(TO_CHAR(Q4, 'FM999,999'), 4, ' ') || ' (' || TO_CHAR(ROUND(Q4 * 100.0 / NULLIF(yearly_total, 0), 1), 'FM990.0') || '%)', 20, ' ') || '|' ||
        RPAD('     ' || LPAD(TO_CHAR(yearly_total, 'FM999,999'), 7, ' '), 20) || '|' ||
        '    ' ||
        CASE 
            WHEN trend_percentage > 0 THEN CHR(27) || '[31m'  -- Red
            WHEN trend_percentage < 0 THEN CHR(27) || '[32m'  -- Green
            ELSE CHR(27) || '[33m'                            -- Yellow
        END
        || LPAD(TO_CHAR(trend_percentage, 'FM990.00'), 6, ' ') || '%' 
        || CHR(27) || '[0m' -- Reset color after number, then append %
        || RPAD(' ', 3, ' ') || '|' AS row_data
    FROM pivot_data
)
-- Final display output
SELECT
    RPAD(' ',14) || '+' || RPAD('-', 22, '-') || '+' || RPAD('-', 83, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 14, '-') || '+' AS report_line
FROM dual
UNION ALL
SELECT
    RPAD(' ',14) || '|' || RPAD(' ', 22, ' ') || '|' || RPAD('                                 Total Cancellation                                 ', 83, ' ') || '|' || RPAD(' ', 20, ' ') || '|' || RPAD(' ', 14, ' ') || '|'
FROM dual
UNION ALL
SELECT
    RPAD(' ',14) || '|         ' || RPAD('Year', 13, ' ') || '|' || RPAD('____________________________________________________________________', 83, '_') || '|' || RPAD('    Yearly Total    ', 20, ' ') || '|' || RPAD('    Trends    ', 14, ' ') || '|'
FROM dual
UNION ALL
SELECT
    RPAD(' ',14) || '|' || RPAD(' ', 22, ' ') || '|' || RPAD('         Q1         |         Q2         |         Q3         |         Q4         ', 83, ' ') || '|' || RPAD(' ', 20, ' ') || '|' || RPAD(' ', 14, ' ') || '|'
FROM dual
UNION ALL
SELECT
    RPAD(' ',14) || '+' || RPAD('-', 22, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+'|| RPAD('-', 20, '-') || '+' || RPAD('-', 14, '-') || '+' AS header_line
FROM dual
UNION ALL
SELECT row_data FROM formatted_rows
UNION ALL
SELECT
    RPAD(' ',14) || '+' || RPAD('-', 22, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 20, '-') || '+' || RPAD('-', 14, '-') || '+' AS footer_line
FROM dual;

-- Reset any previous formatting
SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF