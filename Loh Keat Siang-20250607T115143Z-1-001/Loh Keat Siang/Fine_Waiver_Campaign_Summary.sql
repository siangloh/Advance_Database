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
SET LINESIZE 200
SET PAGESIZE 20
SET UNDERLINE OFF
SET HEADING OFF

-- Create the view for the data
CREATE OR REPLACE VIEW V_VoucherSummary AS
SELECT
    v.voucherName AS "Campaign Name",
    TO_CHAR(v.startDate, 'DD/MM/YYYY') AS "Start Date",
    TO_CHAR(v.endDate, 'DD/MM/YYYY') AS "End Date",
    COUNT(f.fineId) AS "Total Waived Fines",
    SUM(f.discountApplied) AS "Total_Waived_Amount_Num",
    TO_CHAR(MAX(f.paymentDate), 'DD/MM/YYYY') AS "Last Waiver Date",
    'RM ' || TO_CHAR(AVG(f.discountApplied), 'FM9,999,999.00') AS "Avg Discount",
    -- Store color info separately from the percentage value to maintain alignment
    TO_CHAR(COUNT(f.fineId) * 100.0 / 
        (SELECT COUNT(*) FROM Fine WHERE voucherId IS NOT NULL AND status = 'Paid'), 
        'FM990.0') || '%' AS "Pct of Total Waivers",
    -- Store color code separately for use in the final display
    CASE
        WHEN (COUNT(f.fineId) * 100.0 / 
             (SELECT COUNT(*) FROM Fine WHERE voucherId IS NOT NULL AND status = 'Paid')) <= 20 
            THEN 'RED'
        WHEN (COUNT(f.fineId) * 100.0 / 
             (SELECT COUNT(*) FROM Fine WHERE voucherId IS NOT NULL AND status = 'Paid')) <= 40 
            THEN 'ORANGE'
        WHEN (COUNT(f.fineId) * 100.0 / 
             (SELECT COUNT(*) FROM Fine WHERE voucherId IS NOT NULL AND status = 'Paid')) <= 60 
            THEN 'YELLOW'
        WHEN (COUNT(f.fineId) * 100.0 / 
             (SELECT COUNT(*) FROM Fine WHERE voucherId IS NOT NULL AND status = 'Paid')) <= 80 
            THEN 'LIGHT_GREEN'
        ELSE 'DARK_GREEN'
    END AS "Color_Code",
    CASE
        WHEN v.endDate < SYSDATE THEN 'Expired'
        WHEN v.startDate > SYSDATE THEN 'Upcoming'
        ELSE 'Active'
    END AS "Campaign Status"
FROM Fine f
JOIN Voucher v ON f.voucherId = v.voucherId
WHERE f.voucherId IS NOT NULL AND f.status = 'Paid'
GROUP BY v.voucherId, v.voucherName, v.startDate, v.endDate;

-- Add report formatting
TTITLE CENTER 'FINE WAIVER CAMPAIGN PERFORMANCE REPORT' SKIP 2
SET TERMOUT OFF
COLUMN today NEW_VALUE _DATE
SELECT TO_CHAR(SYSDATE, 'DD/MM/YYYY') AS today FROM dual;
SET TERMOUT ON
BTITLE CENTER 'Data as of: ' _DATE

-- Break and compute
BREAK ON REPORT
COMPUTE SUM LABEL 'TOTAL' OF "Total Waived Fines" "Total_Waived_Amount_Num" ON REPORT

-- Query with formatted output
WITH OrderedSummary AS (
  SELECT *
  FROM V_VoucherSummary
  ORDER BY
    CASE "Campaign Status"
      WHEN 'Active' THEN 1
      WHEN 'Upcoming' THEN 2
      WHEN 'Expired' THEN 3
    END,
    "Total_Waived_Amount_Num" DESC
)
SELECT
    LPAD(' ', 5) || '+-' || RPAD('-', 25, '-') || '-+-' || RPAD('-', 12, '-') || '-+-' ||
    RPAD('-', 12, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 17, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+' AS table_border
FROM dual
UNION ALL
SELECT
    LPAD(' ', 5) || '| ' || RPAD('Campaign Name', 25, ' ') || ' | ' ||
    RPAD('Start Date', 12, ' ') || ' | ' || RPAD('End Date', 12, ' ') || ' | ' ||
    RPAD('Total Waived', 18, ' ') || ' | ' || RPAD('Total Amount', 15, ' ') || ' | ' ||
    RPAD('Last Waiver Date', 17, ' ') || ' | ' || RPAD('Avg Discount', 15, ' ') || ' | ' ||
    RPAD('Pct of Waivers', 18, ' ') || ' | ' || RPAD('Status', 15, ' ') || ' |'
FROM dual
UNION ALL
SELECT
    LPAD(' ', 5) || '+-' || RPAD('-', 25, '-') || '-+-' || RPAD('-', 12, '-') || '-+-' ||
    RPAD('-', 12, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 17, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+' AS table_border
FROM dual
UNION ALL
SELECT
    LPAD(' ', 5) || '| ' || RPAD(SUBSTR("Campaign Name", 1, 25), 25, ' ') || ' | ' ||
    RPAD("Start Date", 12, ' ') || ' | ' || RPAD("End Date", 12, ' ') || ' | ' ||
    LPAD(TO_CHAR("Total Waived Fines", 'FM999,999'), 18, ' ') || ' | ' ||
    RPAD('RM', 4) || LPAD(TO_CHAR("Total_Waived_Amount_Num", 'FM999,990.00'), 11, ' ') || ' | ' ||
    RPAD(NVL("Last Waiver Date", ' '), 17, ' ') || ' | ' ||
    RPAD(NVL("Avg Discount", ' '), 15, ' ') || ' | ' ||
    -- Apply color codes without affecting spacing
    CASE "Color_Code"
        WHEN 'RED' THEN LPAD(CHR(27) || '[31m' || TRIM("Pct of Total Waivers") || CHR(27) || '[0m', 27, ' ')
        WHEN 'ORANGE' THEN LPAD(CHR(27) || '[38;5;208m' || TRIM("Pct of Total Waivers") || CHR(27) || '[0m', 33, ' ')
        WHEN 'YELLOW' THEN LPAD(CHR(27) || '[33m' || TRIM("Pct of Total Waivers") || CHR(27) || '[0m', 27, ' ')
        WHEN 'LIGHT_GREEN' THEN LPAD(CHR(27) || '[92m' || TRIM("Pct of Total Waivers") || CHR(27) || '[0m', 27, ' ')
        WHEN 'DARK_GREEN' THEN LPAD(CHR(27) || '[32m' || TRIM("Pct of Total Waivers") || CHR(27) || '[0m', 27, ' ')
        ELSE LPAD("Pct of Total Waivers", 27, ' ')
    END || ' | ' ||
    CASE "Color_Code"
        WHEN 'ORANGE' THEN RPAD("Campaign Status", 16, ' ') || ' |'
        ELSE RPAD("Campaign Status", 14, ' ') || ' |'
    END
FROM OrderedSummary
UNION ALL
SELECT
    LPAD(' ', 5) || '+-' || RPAD('-', 25, '-') || '-+-' || RPAD('-', 12, '-') || '-+-' ||
    RPAD('-', 12, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 17, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+' AS table_border
FROM dual
UNION ALL
-- Add totals row
SELECT
    LPAD(' ', 5) || '| ' || RPAD('TOTAL', 25, ' ') || ' | ' ||
    RPAD(' ', 12, ' ') || ' | ' || RPAD(' ', 12, ' ') || ' | ' ||
    LPAD(TO_CHAR((SELECT SUM("Total Waived Fines") FROM V_VoucherSummary), '999,999'), 18, ' ') || ' | ' ||
    LPAD('RM ' || TO_CHAR((SELECT SUM("Total_Waived_Amount_Num") FROM V_VoucherSummary), '999,999.00'), 15, ' ') || ' | ' ||
    RPAD(' ', 17, ' ') || ' | ' ||
    RPAD(' ', 15, ' ') || ' | ' ||
    RPAD(' ', 18, ' ') || ' | ' ||
    RPAD(' ', 15, ' ') || ' |'
FROM dual
UNION ALL
SELECT
    LPAD(' ', 5) || '+-' || RPAD('-', 25, '-') || '-+-' || RPAD('-', 12, '-') || '-+-' ||
    RPAD('-', 12, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 17, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+-' || RPAD('-', 18, '-') || '-+-' ||
    RPAD('-', 15, '-') || '-+' AS table_border
FROM dual;

SET UNDERLINE ON
SET HEADING ON
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF
BTITLE OFF