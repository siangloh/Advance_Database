SET SERVEROUTPUT ON;
SET LINESIZE 1PRINT_LINE50
SET PAGESIZE 150
SET LINESIZE 220
SET TRIMSPOOL ON;
SET VERIFY OFF;
SET DEFINE ON;

-- Clear any existing variables
UNDEFINE startYearInput
UNDEFINE endYearInput
UNDEFINE quarterInput

-- Sequence for report generation
CREATE SEQUENCE LIBRARY_REPORT_SEQ
    START WITH 1000
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

-- Prompt for user input
PROMPT
ACCEPT startYearInput CHAR PROMPT 'Enter the start year (YYYY): '
ACCEPT endYearInput CHAR PROMPT 'Enter the end year (YYYY): '
ACCEPT quarterInput CHAR PROMPT 'Enter the quarter (0-4) - 0 means all quarter: '

CREATE OR REPLACE PROCEDURE LIBRARY_INCOME_REPORT(
    v_start_year IN NUMBER,
    v_end_year IN NUMBER,
    v_quarter IN NUMBER DEFAULT NULL -- Optional quarter parameter (1-4), NULL for full year
)
AS
    -- Report ID from sequence
    v_report_id         NUMBER;
    
    -- Date range for the report
    v_start_date        DATE;
    v_end_date          DATE;
    v_prev_start_date   DATE; -- Added for quarter comparison
    v_prev_end_date     DATE; -- Added for quarter comparison
    
    -- Report statistics
    v_total_income          NUMBER(12,2) := 0;
    v_total_income_q          NUMBER(12,2) := 0;
    v_membership_income     NUMBER(12,2) := 0;
    v_membership_income_start     NUMBER(12,2) := 0;
    v_membership_income_end     NUMBER(12,2) := 0;
    v_room_income           NUMBER(12,2) := 0;
    v_room_income_start           NUMBER(12,2) := 0;
    v_room_income_end           NUMBER(12,2) := 0;
    v_fine_income           NUMBER(12,2) := 0;
    v_fine_income_start           NUMBER(12,2) := 0;
    v_fine_income_end           NUMBER(12,2) := 0;
    
    -- Year-over-year comparison
    v_prev_total_income     NUMBER(12,2) := 0;
    v_prev_total_income_q     NUMBER(12,2) := 0;
    v_prev_membership_income NUMBER(12,2) := 0;
    v_prev_room_income      NUMBER(12,2) := 0;
    v_prev_fine_income      NUMBER(12,2) := 0;
    v_membership_income_q  NUMBER(12,2) := 0;
    v_room_income_q       NUMBER(12,2) := 0;
    v_fine_income_q       NUMBER(12,2) := 0;
    
    -- Overall trend calculation
    v_overall_trend NUMBER := 0;

    -- Format utilities
    v_color_normal       VARCHAR2(10) := 'GREEN';
    v_color_warning      VARCHAR2(10) := 'YELLOW';
    v_color_alert        VARCHAR2(10) := 'RED';

    -- Table formatting variables
    v_line      VARCHAR2(100) := '-';
    v_line_sep  VARCHAR2(100) := '|';
    v_cross     VARCHAR2(100) := '+';

    -- Variable Created
    v_membership_percentage NUMBER := 0; 
    v_room_percentage NUMBER := 0;       
    v_fine_percentage NUMBER := 0;       
    
    -- Custom types for yearly and quarterly data
    TYPE t_income_rec IS RECORD (
        year_num         NUMBER,
        quarter_num      NUMBER,
        membership_income NUMBER(12,2),
        room_income      NUMBER(12,2),
        fine_income      NUMBER(12,2),
        total_income     NUMBER(12,2),
        growth_rate      NUMBER(12,2), -- Growth rate compared to previous quarter
        year_growth_rate NUMBER(12,2)  -- Growth rate compared to same quarter last year
    );
    
    TYPE t_income_tab IS TABLE OF t_income_rec INDEX BY PLS_INTEGER;
    v_yearly_income       t_income_tab;
    v_quarterly_income    t_income_tab;
        
    -- Cursor for membership income
    CURSOR c_membership_income IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE t.renewalId IS NOT NULL AND t.transactionDate BETWEEN v_start_date AND v_end_date;
    
    CURSOR c_membership_income_start IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE t.renewalId IS NOT NULL AND EXTRACT(YEAR FROM t.transactionDate) = v_start_year;

    CURSOR c_membership_income_end IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE t.renewalId IS NOT NULL AND EXTRACT(YEAR FROM t.transactionDate) = v_end_year;

    -- Cursor for room reservation income
    CURSOR c_room_income IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t on rr.reserveId = t.reserveId
        WHERE t.reserveId IS NOT NULL AND t.transactionDate BETWEEN v_start_date AND v_end_date;
    
    CURSOR c_room_income_start IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t on rr.reserveId = t.reserveId
        WHERE t.reserveId IS NOT NULL AND EXTRACT(YEAR FROM t.transactionDate) = v_start_year;
    
    CURSOR c_room_income_end IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t on rr.reserveId = t.reserveId
        WHERE t.reserveId IS NOT NULL AND EXTRACT(YEAR FROM t.transactionDate) = v_end_year;
    
    -- Cursor for fine income
    CURSOR c_fine_income IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t ON f.fineId = t.fineId
        WHERE t.fineId IS NOT NULL AND f.status = 'Paid' AND t.transactionDate BETWEEN v_start_date AND v_end_date;
    
    CURSOR c_fine_income_start IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t ON f.fineId = t.fineId
        WHERE t.fineId IS NOT NULL AND f.status = 'Paid' AND EXTRACT(YEAR FROM t.transactionDate) = v_start_year;
    
    CURSOR c_fine_income_end IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t ON f.fineId = t.fineId
        WHERE t.fineId IS NOT NULL AND f.status = 'Paid' AND EXTRACT(YEAR FROM t.transactionDate) = v_end_year;
    
    -- Cursor for previous period membership income
    CURSOR c_prev_membership_income IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = v_end_year AND TO_CHAR(t.transactionDate, 'Q') = v_quarter;
    
    CURSOR c_membership_income_q IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = v_start_year AND TO_CHAR(t.transactionDate, 'Q') = v_quarter;
    
    -- Cursor for previous period room income
    CURSOR c_prev_room_income IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t ON rr.reserveId = t.reserveId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = v_end_year AND TO_CHAR(t.transactionDate, 'Q') = v_quarter;
    
    CURSOR c_room_income_q IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t ON rr.reserveId = t.reserveId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = v_start_year AND TO_CHAR(t.transactionDate, 'Q') = v_quarter;
    
    -- Cursor for previous period fine income
    CURSOR c_prev_fine_income IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t ON f.fineId = t.fineId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = v_end_year AND TO_CHAR(t.transactionDate, 'Q') = v_quarter;
    
    CURSOR c_fine_income_q IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t ON f.fineId = t.fineId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = v_start_year AND TO_CHAR(t.transactionDate, 'Q') = v_quarter;
    
    -- Cursor for yearly membership income
    CURSOR c_yearly_membership_income(p_year NUMBER) IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = p_year;
    
    -- Cursor for yearly room income
    CURSOR c_yearly_room_income(p_year NUMBER) IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t ON rr.reserveId = t.reserveId
        WHERE EXTRACT(YEAR FROM t.transactionDate) = p_year;

    -- Cursor for yearly fine income
    CURSOR c_yearly_fine_income(p_year NUMBER) IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t ON f.fineId = t.fineId
        WHERE f.status = 'Paid' AND EXTRACT(YEAR FROM t.transactionDate) = p_year;
    
    -- Cursor for quarterly membership income
    CURSOR c_quarterly_membership(p_year NUMBER, p_quarter NUMBER) IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Renewal r
        JOIN Transaction t ON r.renewalId = t.renewalId
        WHERE t.transactionDate BETWEEN 
            TO_DATE('01/' || TO_CHAR((p_quarter - 1) * 3 + 1) || '/' || p_year, 'DD/MM/YYYY') 
            AND 
            ADD_MONTHS(TO_DATE('01/' || TO_CHAR((p_quarter - 1) * 3 + 1) || '/' || p_year, 'DD/MM/YYYY'), 3) - 1;
    
    -- Cursor for quarterly room income
    CURSOR c_quarterly_room(p_year NUMBER, p_quarter NUMBER) IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM RoomReservation rr
        JOIN Transaction t ON rr.reserveId = t.reserveId
        WHERE t.transactionDate BETWEEN 
            TO_DATE('01/' || TO_CHAR((p_quarter - 1) * 3 + 1) || '/' || p_year, 'DD/MM/YYYY') 
            AND 
            ADD_MONTHS(TO_DATE('01/' || TO_CHAR((p_quarter - 1) * 3 + 1) || '/' || p_year, 'DD/MM/YYYY'), 3) - 1;
    
    -- Cursor for quarterly fine income
    CURSOR c_quarterly_fine(p_year NUMBER, p_quarter NUMBER) IS
        SELECT NVL(SUM(t.amount), 0) as total_amount
        FROM Fine f
        JOIN Transaction t on f.fineId = t.fineId
        WHERE f.status = 'Paid' AND t.transactionDate BETWEEN 
            TO_DATE('01/' || TO_CHAR((p_quarter - 1) * 3 + 1) || '/' || p_year, 'DD/MM/YYYY') 
            AND 
            ADD_MONTHS(TO_DATE('01/' || TO_CHAR((p_quarter - 1) * 3 + 1) || '/' || p_year, 'DD/MM/YYYY'), 3) - 1;
    
    -- Forward declarations for local procedures and functions
    PROCEDURE print_header(p_title IN VARCHAR2);
    PROCEDURE print_section(p_title IN VARCHAR2);
    PROCEDURE print_line(p_char IN CHAR DEFAULT '-', p_cross IN CHAR DEFAULT v_line_sep);
    PROCEDURE print_footer;
    
    FUNCTION format_amount(p_amount IN NUMBER) RETURN VARCHAR2;
    FUNCTION format_percent(p_value IN NUMBER) RETURN VARCHAR2;
    FUNCTION get_trend_indicator(p_current IN NUMBER, p_previous IN NUMBER) RETURN VARCHAR2;
    FUNCTION format_trend(p_value IN NUMBER) RETURN VARCHAR2;
    
    PROCEDURE load_income_data;
    PROCEDURE load_yearly_data;
    PROCEDURE load_quarterly_data;
    PROCEDURE calculate_growth_rates;
    
    PROCEDURE generate_yearly_report;
    PROCEDURE generate_income_breakdown;
    
    -- Format money amounts
    FUNCTION format_amount(p_amount IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN 'RM ' || LPAD(TO_CHAR(NVL(p_amount, 0), 'FM999,999,990.00'), 9);
    END format_amount;
    
    -- Format percentage
    FUNCTION format_percent(p_value IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_value, 0), 'FM990.0') || '%';
    END format_percent;
    
    -- Calculate trend indicator with percentage 
    FUNCTION get_trend_indicator(p_current IN NUMBER, p_previous IN NUMBER) RETURN VARCHAR2 IS
        v_percent NUMBER;
        v_trend VARCHAR2(50);
        -- ANSI color codes
        v_red     CONSTANT VARCHAR2(10) := CHR(27) || '[31m'; -- Red for negative trends
        v_green   CONSTANT VARCHAR2(10) := CHR(27) || '[32m'; -- Green for positive trends
        v_blue    CONSTANT VARCHAR2(10) := CHR(27) || '[34m'; -- Blue for stable trends
        v_reset   CONSTANT VARCHAR2(10) := CHR(27) || '[0m';  -- Reset to default color
    BEGIN
        IF p_previous = 0 THEN
            RETURN v_blue || 'N/A' || v_reset;
        END IF;
        
        v_percent := ((p_current - p_previous) / p_previous) * 100;
        
        IF v_percent > 0 THEN
            v_trend := v_green || 'UP ' || TO_CHAR(ABS(v_percent), 'FM990.0') || '%' || v_reset;
        ELSIF v_percent < 0 THEN
            v_trend := v_red || 'DOWN ' || TO_CHAR(ABS(v_percent), 'FM990.0') || '%' || v_reset;
        ELSE
            v_trend := v_blue || 'STABLE 0.0%' || v_reset;
        END IF;
        
        RETURN v_trend;
    END get_trend_indicator;

    -- Add this function to your code, inside the LIBRARY_INCOME_REPORT procedure
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
            v_formatted_trend := v_green || TO_CHAR(p_value, 'FM9,990.00') || '%' || v_reset;
        ELSIF p_value > 5 THEN
            -- Moderate positive trend (light green)
            v_formatted_trend := v_green || TO_CHAR(p_value, 'FM9,990.00') || '%' || v_reset;
        ELSIF p_value > 0 THEN
            -- Slight positive trend (yellow-green)
            v_formatted_trend := v_yellow || TO_CHAR(p_value, 'FM9,990.00') || '%' || v_reset;
        ELSIF p_value = 0 THEN
            -- Stable/neutral (blue)
            v_formatted_trend := v_blue || '0.00%' || v_reset;
        ELSIF p_value > -5 THEN
            -- Slight negative trend (light red)
            v_formatted_trend := v_yellow || TO_CHAR(p_value, 'FM9,990.00') || '%' || v_reset;
        ELSIF p_value > -10 THEN
            -- Moderate negative trend (medium red)
            v_formatted_trend := v_red || TO_CHAR(p_value, 'FM9,990.00') || '%' || v_reset;
        ELSE
            -- Strong negative trend (dark red)
            v_formatted_trend := v_red || TO_CHAR(p_value, 'FM9,990.00') || '%' || v_reset;
        END IF;
        
        RETURN v_formatted_trend;
    END format_trend;
    
    -- Print formatted header
    PROCEDURE print_header(p_title IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CHR(10));
        print_line('=', v_cross);
        DBMS_OUTPUT.PUT_LINE(v_line_sep || LPAD(p_title, 105, ' ') || LPAD(v_line_sep, 61));
        print_line('=', v_cross);
    END print_header;

    -- Print section header
    PROCEDURE print_section(p_title IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CHR(10));
        print_line(v_line, v_cross);
        DBMS_OUTPUT.PUT_LINE(v_line_sep || LPAD(p_title, 90, ' ') || LPAD(v_line_sep, 76));
        print_line(v_line, v_cross);
    END print_section;
    
    -- Print horizontal line
    PROCEDURE print_line(p_char IN CHAR DEFAULT '-', p_cross IN CHAR DEFAULT v_line_sep) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_cross || RPAD(p_char, 165, p_char) || p_cross);
    END print_line;
    
    -- Print footer
    PROCEDURE print_footer IS
    BEGIN
        print_line('=', v_cross);
        DBMS_OUTPUT.PUT_LINE(v_line_sep || LPAD('Report ID: ' || v_report_id || ' | Generated on: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'), 110, ' ') || LPAD(v_line_sep, 56));
        print_line('=', v_cross);
        DBMS_OUTPUT.PUT_LINE(CHR(10));
    END print_footer;
    
    -- Load all income data for the specified period using explicit cursors
PROCEDURE load_income_data IS
    v_temp_amount NUMBER(12,2);
    BEGIN
    -- Set date range based on quarter (if specified)
    IF v_quarter IS NOT NULL AND v_quarter IN (1,2,3,4) THEN
        -- Calculate quarter start and end dates for the specified year
        v_start_date := TO_DATE('01/' || TO_CHAR((v_quarter - 1) * 3 + 1) || '/' || v_start_year, 'DD/MM/YYYY');
        v_end_date := ADD_MONTHS(v_start_date, 3) - 1;
        
        -- Previous period dates (same quarter previous year)
        v_prev_start_date := ADD_MONTHS(v_start_date, -12);
        v_prev_end_date := ADD_MONTHS(v_end_date, -12);
        
        -- Load quarterly data - ADDED THIS SECTION
        OPEN c_membership_income_q;
        FETCH c_membership_income_q INTO v_membership_income_q;
        CLOSE c_membership_income_q;
        
        OPEN c_room_income_q;
        FETCH c_room_income_q INTO v_room_income_q;
        CLOSE c_room_income_q;
        
        OPEN c_fine_income_q;
        FETCH c_fine_income_q INTO v_fine_income_q;
        CLOSE c_fine_income_q;
        
        -- Calculate total quarterly income
        v_total_income_q := v_membership_income_q + v_room_income_q + v_fine_income_q;
        
        -- Load previous year same quarter data for comparison
        OPEN c_prev_membership_income;
        FETCH c_prev_membership_income INTO v_prev_membership_income;
        CLOSE c_prev_membership_income;
        
        OPEN c_prev_room_income;
        FETCH c_prev_room_income INTO v_prev_room_income;
        CLOSE c_prev_room_income;
        
        OPEN c_prev_fine_income;
        FETCH c_prev_fine_income INTO v_prev_fine_income;
        CLOSE c_prev_fine_income;
        
        v_prev_total_income_q := v_prev_membership_income + v_prev_room_income + v_prev_fine_income;
    ELSE
        -- Full year range
        v_start_date := TO_DATE('01/01/' || v_start_year, 'DD/MM/YYYY');
        v_end_date := TO_DATE('31/12/' || v_end_year, 'DD/MM/YYYY');
        
        -- Previous period not used for multi-year comparison
        v_prev_start_date := TO_DATE('01/01/' || (v_start_year - 1), 'DD/MM/YYYY');
        v_prev_end_date := TO_DATE('31/12/' || (v_start_year - 1), 'DD/MM/YYYY');
    END IF;
    
    -- Use explicit cursors to load membership income for current period
    OPEN c_membership_income;
    FETCH c_membership_income INTO v_membership_income;
    CLOSE c_membership_income;

    -- Load start year membership income
    OPEN c_membership_income_start;
    FETCH c_membership_income_start INTO v_membership_income_start;
    CLOSE c_membership_income_start;

    -- Load end year membership income
    OPEN c_membership_income_end;
    FETCH c_membership_income_end INTO v_membership_income_end;
    CLOSE c_membership_income_end;
    
      -- Use explicit cursors to load room reservation income
        OPEN c_room_income;
        FETCH c_room_income INTO v_room_income;
        CLOSE c_room_income;
        
        OPEN c_room_income_start;
        FETCH c_room_income_start INTO v_room_income_start;
        CLOSE c_room_income_start;
        
        OPEN c_room_income_end;
        FETCH c_room_income_end INTO v_room_income_end;
        CLOSE c_room_income_end;
        
        -- Use explicit cursors to load fine income
        OPEN c_fine_income;
        FETCH c_fine_income INTO v_fine_income;
        CLOSE c_fine_income;
        
        OPEN c_fine_income_start;
        FETCH c_fine_income_start INTO v_fine_income_start;
        CLOSE c_fine_income_start;
        
        OPEN c_fine_income_end;
        FETCH c_fine_income_end INTO v_fine_income_end;
        CLOSE c_fine_income_end;
    
    -- Calculate total income based on whether we're doing quarterly or yearly report
    IF v_quarter IS NOT NULL AND v_quarter IN (1,2,3,4) THEN
        -- For quarterly report, use the quarter-specific data
        v_prev_total_income:= v_membership_income_q + v_room_income_q + v_fine_income_q;
        v_total_income:= v_prev_membership_income + v_prev_room_income + v_prev_fine_income;
    ELSE    
        -- For yearly report, use the start and end year data for comparison
        v_total_income := v_membership_income_end + v_room_income_end + v_fine_income_end;
        v_prev_total_income := v_membership_income_start + v_room_income_start + v_fine_income_start;
    END IF;
    
    -- For calculating overall trend
    IF v_quarter IS NULL OR v_quarter = 0 THEN
        -- For yearly report - compare start and end year
        v_overall_trend := ((v_total_income - v_prev_total_income) / NULLIF(v_prev_total_income, 0)) * 100;
    ELSE
        -- For quarterly report - compare with same quarter previous year
        v_overall_trend := ((v_total_income - v_prev_total_income) / NULLIF(v_prev_total_income, 0)) * 100;
    END IF;
    END load_income_data;
    
    -- Load yearly income data for trend analysis using explicit cursors
    PROCEDURE load_yearly_data IS
        v_year_index NUMBER := 0;
        v_membership_amount NUMBER(12,2);
        v_room_amount NUMBER(12,2);
        v_fine_amount NUMBER(12,2);
    BEGIN
        -- Loop through each year
        FOR yr IN v_start_year..v_end_year LOOP
            v_year_index := v_year_index + 1;
            
            -- Store year
            v_yearly_income(v_year_index).year_num := yr;
            v_yearly_income(v_year_index).quarter_num := 0; -- 0 for full year
            
            -- Get membership income for this year using cursor
            OPEN c_yearly_membership_income(yr);
            FETCH c_yearly_membership_income INTO v_membership_amount;
            CLOSE c_yearly_membership_income;
            v_yearly_income(v_year_index).membership_income := v_membership_amount;
            
            -- Get room reservation income for this year using cursor
            OPEN c_yearly_room_income(yr);
            FETCH c_yearly_room_income INTO v_room_amount;
            CLOSE c_yearly_room_income;
            v_yearly_income(v_year_index).room_income := v_room_amount;
            
            -- Get fine income for this year using cursor
            OPEN c_yearly_fine_income(yr);
            FETCH c_yearly_fine_income INTO v_fine_amount;
            CLOSE c_yearly_fine_income;
            v_yearly_income(v_year_index).fine_income := v_fine_amount;
            
            -- Calculate total income for the year
            v_yearly_income(v_year_index).total_income := 
                v_yearly_income(v_year_index).membership_income +
                v_yearly_income(v_year_index).room_income +
                v_yearly_income(v_year_index).fine_income;
                
            -- Initialize growth rates (will be calculated later)
            v_yearly_income(v_year_index).growth_rate := 0;
            v_yearly_income(v_year_index).year_growth_rate := 0;
        END LOOP;
    END load_yearly_data;
    
    -- Load quarterly income data for detailed analysis using explicit cursors
    PROCEDURE load_quarterly_data IS
        v_quarter_index NUMBER := 0;
        v_membership_amount NUMBER(12,2);
        v_room_amount NUMBER(12,2);
        v_fine_amount NUMBER(12,2);
    BEGIN
        -- Loop through each year
        FOR yr IN v_start_year..v_end_year LOOP
            -- Loop through each quarter (if specific quarter not requested)
            FOR qtr IN 1..4 LOOP
                IF v_quarter IS NULL OR v_quarter = qtr OR v_quarter = 0 THEN
                    v_quarter_index := v_quarter_index + 1;
                    
                    -- Store year and quarter
                    v_quarterly_income(v_quarter_index).year_num := yr;
                    v_quarterly_income(v_quarter_index).quarter_num := qtr;
                    
                    -- Get membership income for this quarter using cursor
                    OPEN c_quarterly_membership(yr, qtr);
                    FETCH c_quarterly_membership INTO v_membership_amount;
                    CLOSE c_quarterly_membership;
                    v_quarterly_income(v_quarter_index).membership_income := v_membership_amount;
                    
                    -- Get room reservation income for this quarter using cursor
                    OPEN c_quarterly_room(yr, qtr);
                    FETCH c_quarterly_room INTO v_room_amount;
                    CLOSE c_quarterly_room;
                    v_quarterly_income(v_quarter_index).room_income := v_room_amount;
                    
                    -- Get fine income for this quarter using cursor
                    OPEN c_quarterly_fine(yr, qtr);
                    FETCH c_quarterly_fine INTO v_fine_amount;
                    CLOSE c_quarterly_fine;
                    v_quarterly_income(v_quarter_index).fine_income := v_fine_amount;
                    
                    -- Calculate total income for the quarter
                    v_quarterly_income(v_quarter_index).total_income := 
                        v_quarterly_income(v_quarter_index).membership_income +
                        v_quarterly_income(v_quarter_index).room_income +
                        v_quarterly_income(v_quarter_index).fine_income;
                        
                    -- Initialize growth rates (will be calculated later)
                    v_quarterly_income(v_quarter_index).growth_rate := 0;
                    v_quarterly_income(v_quarter_index).year_growth_rate := 0;
                END IF;
            END LOOP;
        END LOOP;
    END load_quarterly_data;
    
    -- Calculate growth rates for yearly and quarterly data
    PROCEDURE calculate_growth_rates IS
    BEGIN
        -- Calculate yearly growth rates
        FOR i IN 2..v_yearly_income.COUNT LOOP
            IF v_yearly_income(i-1).total_income > 0 THEN
                v_yearly_income(i).growth_rate := 
                    ((v_yearly_income(i).total_income - v_yearly_income(i-1).total_income) / 
                     v_yearly_income(i-1).total_income) * 100;
            ELSE
                v_yearly_income(i).growth_rate := 0;
            END IF;
        END LOOP;
        
        -- Calculate quarterly growth rates (quarter-to-quarter)
        FOR i IN 2..v_quarterly_income.COUNT LOOP
            IF v_quarterly_income(i-1).total_income > 0 THEN
                v_quarterly_income(i).growth_rate := 
                    ((v_quarterly_income(i).total_income - v_quarterly_income(i-1).total_income) / 
                     v_quarterly_income(i-1).total_income) * 100;
            END IF;
        END LOOP;
        
        -- Calculate quarterly year-over-year growth rates
        FOR i IN 1..v_quarterly_income.COUNT LOOP
            DECLARE
                v_prev_year NUMBER := v_quarterly_income(i).year_num - 1;
                v_same_quarter NUMBER := v_quarterly_income(i).quarter_num;
                v_prev_year_income NUMBER := 0;
                v_found BOOLEAN := FALSE;
            BEGIN
                -- Find the same quarter from previous year
                FOR j IN 1..v_quarterly_income.COUNT LOOP
                    IF v_quarterly_income(j).year_num = v_prev_year AND 
                       v_quarterly_income(j).quarter_num = v_same_quarter THEN
                        v_prev_year_income := v_quarterly_income(j).total_income;
                        v_found := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
                
                -- Calculate year-over-year growth rate if previous year data exists
                IF v_found AND v_prev_year_income > 0 THEN
                    v_quarterly_income(i).year_growth_rate := 
                        ((v_quarterly_income(i).total_income - v_prev_year_income) / 
                         v_prev_year_income) * 100;
                END IF;
            END;
        END LOOP;
    END calculate_growth_rates;

    -- Generate yearly income report
    PROCEDURE generate_yearly_report IS
        v_membership_percent NUMBER;
        v_room_percent NUMBER;
        v_fine_percent NUMBER;
        v_avg_growth NUMBER := 0;
    BEGIN
        print_section(LPAD('YEARLY INCOME REPORT', 90));
        IF v_total_income > 0 THEN
            v_membership_percent := (v_membership_income / v_total_income) * 100;
            v_room_percent := (v_room_income / v_total_income) * 100;
            v_fine_percent := (v_fine_income / v_total_income) * 100;
        ELSE
            v_membership_percent := 0;
            v_room_percent := 0;
            v_fine_percent := 0;
        END IF;

        -- Display table header
        DBMS_OUTPUT.PUT_LINE(v_line_sep || RPAD('  Year', 8) || v_line_sep ||
                           RPAD('  Quarter', 10) || v_line_sep ||
                           RPAD('      Membership', 22) || v_line_sep ||
                           RPAD('    Room Reservation', 23) || v_line_sep ||
                           RPAD('          Fines', 23) || v_line_sep ||
                           RPAD('   Total Income', 18) || v_line_sep ||
                           RPAD('  Growth Rate', 15) || v_line_sep ||
                           RPAD(' Growth Rate Yearly', 20) || v_line_sep ||
                           RPAD('  Primary Driver', 18) || v_line_sep);
        print_line(v_line);
        
        -- First, display quarterly data
        DECLARE
            v_current_year NUMBER := 0;
            v_year_total NUMBER(12,2) := 0;
            v_year_membership NUMBER(12,2) := 0;
            v_year_room NUMBER(12,2) := 0;
            v_year_fine NUMBER(12,2) := 0;
            v_yearly_growth_rate NUMBER := 0;
            v_primary_driver VARCHAR2(30) := 'Initial Year';
        BEGIN
        FOR i IN 1..v_quarterly_income.COUNT LOOP
            -- Handle year transition and reset accumulators
            IF v_current_year != v_quarterly_income(i).year_num THEN
                -- Calculate yearly growth rate when year changes
                IF v_current_year > 0 THEN
                    FOR j IN 1..v_yearly_income.COUNT LOOP
                        IF v_yearly_income(j).year_num = v_current_year THEN
                            v_yearly_growth_rate := v_yearly_income(j).growth_rate;
                            EXIT;
                        END IF;
                    END LOOP;
                END IF;
                
                -- Reset for new year
                v_current_year := v_quarterly_income(i).year_num;
                v_year_total := 0;
                v_year_membership := 0;
                v_year_room := 0;
                v_year_fine := 0;
            END IF;
            
            -- Accumulate yearly totals
            v_year_membership := v_year_membership + v_quarterly_income(i).membership_income;
            v_year_room := v_year_room + v_quarterly_income(i).room_income;
            v_year_fine := v_year_fine + v_quarterly_income(i).fine_income;
            v_year_total := v_year_total + v_quarterly_income(i).total_income;
            
            -- Calculate percentages for current quarter
            DECLARE
                v_mem_pct NUMBER := 0;
                v_room_pct NUMBER := 0;
                v_fine_pct NUMBER := 0;
                v_q_total NUMBER := v_quarterly_income(i).total_income;
                v_growth_str VARCHAR2(20);
                v_yearly_growth_str VARCHAR2(20);
                v_membership_change NUMBER := 0;
                v_room_change NUMBER := 0;
                v_fine_change NUMBER := 0;
            BEGIN
                -- Calculate percentage contributions
                IF v_q_total > 0 THEN
                    v_mem_pct := (v_quarterly_income(i).membership_income / v_q_total) * 100;
                    v_room_pct := (v_quarterly_income(i).room_income / v_q_total) * 100;
                    v_fine_pct := (v_quarterly_income(i).fine_income / v_q_total) * 100;
                END IF;
                
                -- Determine primary growth driver (for quarters within same year)
                    v_membership_change := v_quarterly_income(i).membership_income;
                    v_room_change := v_quarterly_income(i).room_income;
                    v_fine_change := v_quarterly_income(i).fine_income;
                    
                    -- Identify primary driver based on largest absolute change
                    IF v_membership_change = v_room_change AND v_room_change = v_fine_change THEN 
                        v_primary_driver := '-';
                    ELSIF v_membership_change >= v_room_change AND v_membership_change >= v_fine_change THEN
                        v_primary_driver := 'Membership';
                    ELSIF v_room_change >= v_fine_change THEN
                        v_primary_driver := 'Room Reservation';
                    ELSE
                        v_primary_driver := 'Fine Collection';
                    END IF;

                v_growth_str := CASE 
                                WHEN i = 1 OR v_quarterly_income(i).year_num != v_quarterly_income(i-1).year_num THEN format_trend(0)
                                ELSE format_trend(v_quarterly_income(i).growth_rate)
                                END;
                
                v_yearly_growth_str := CASE
                                    WHEN v_quarterly_income(i).year_growth_rate = 0 THEN format_trend(0)
                                    ELSE format_trend(v_quarterly_income(i).year_growth_rate)
                                    END;

                -- Output formatted quarterly line
                DBMS_OUTPUT.PUT_LINE(
                    v_line_sep || LPAD(v_quarterly_income(i).year_num, 6) || LPAD(v_line_sep, 3) ||
                    LPAD('Q' || v_quarterly_income(i).quarter_num, 6) || LPAD(v_line_sep, 5) ||
                    LPAD(format_amount(v_quarterly_income(i).membership_income) || LPAD(' (' || format_percent(v_mem_pct) || ')', 8), 21) || LPAD(v_line_sep, 2) ||
                    LPAD(format_amount(v_quarterly_income(i).room_income) || LPAD(' (' || format_percent(v_room_pct) || ')', 8), 22) || LPAD(v_line_sep, 2) ||
                    LPAD(format_amount(v_quarterly_income(i).fine_income) || LPAD(' (' || format_percent(v_fine_pct) || ')', 8), 22) || LPAD(v_line_sep, 2) ||
                    LPAD(format_amount(v_quarterly_income(i).total_income), 15) || LPAD(v_line_sep, 4) ||
                    LPAD(v_growth_str, 20) || LPAD(v_line_sep, 5) ||
                    LPAD(v_yearly_growth_str, 30) || LPAD(v_line_sep, 6) ||
                    LPAD(v_primary_driver, 17) || LPAD(v_line_sep, 2)
                );
            END;
        END LOOP;
        END;
        
        -- Display overall total
        print_line(v_line);
        DECLARE
            v_overall_membership NUMBER(12,2) := 0;
            v_overall_room NUMBER(12,2) := 0;
            v_overall_fine NUMBER(12,2) := 0;
            v_overall_total NUMBER(12,2) := 0;
        BEGIN
            FOR i IN 1..v_quarterly_income.COUNT LOOP
                v_overall_membership := v_overall_membership + v_quarterly_income(i).membership_income;
                v_overall_room := v_overall_room + v_quarterly_income(i).room_income;
                v_overall_fine := v_overall_fine + v_quarterly_income(i).fine_income;
                v_overall_total := v_overall_total + v_quarterly_income(i).total_income;
            END LOOP;
            
            IF v_overall_total > 0 THEN
                v_membership_percent := (v_overall_membership / v_overall_total) * 100;
                v_room_percent := (v_overall_room / v_overall_total) * 100;
                v_fine_percent := (v_overall_fine / v_overall_total) * 100;
                v_membership_percentage := (v_overall_membership / v_overall_total) * 100;
                v_room_percentage := (v_overall_room / v_overall_total) * 100;
                v_fine_percentage := (v_overall_fine / v_overall_total) * 100;
            ELSE
                v_membership_percent := 0;
                v_room_percent := 0;
                v_fine_percent := 0;
                v_membership_percentage := 0;
                v_room_percentage := 0;
                v_fine_percentage := 0;
            END IF;

            DBMS_OUTPUT.PUT_LINE(v_line_sep ||
                RPAD('       TOTAL', 19) ||  v_line_sep ||
                LPAD(format_amount(v_overall_membership) || ' (' || format_percent(v_membership_percent) || ')', 21) || LPAD(v_line_sep, 2) ||
                LPAD(format_amount(v_overall_room) || ' (' || format_percent(v_room_percent) || ')', 22) || LPAD(v_line_sep, 2) ||
                LPAD(format_amount(v_overall_fine) || ' (' || format_percent(v_fine_percent) || ')', 22) || LPAD(v_line_sep, 2) ||
                LPAD(format_amount(v_overall_total), 15) || 
                LPAD(v_line_sep, 4) || LPAD(v_line_sep,56)
            );
            print_line(v_line, v_cross);
        END;
    END generate_yearly_report;
    
    -- Generate income breakdown and analysis

PROCEDURE generate_income_breakdown IS
    v_top_source VARCHAR2(30);
    v_growth_indicator VARCHAR2(30);
    v_membership_growth NUMBER;
    v_room_growth NUMBER;
    v_fine_growth NUMBER;
BEGIN
    print_section('INCOME ANALYSIS');
    
    -- Calculate growth rates based on whether we're analyzing quarterly or yearly data
    IF v_quarter IS NULL OR v_quarter = 0 THEN
        -- Yearly growth calculations
        v_membership_growth := ((v_membership_income_end - v_membership_income_start) / NULLIF(v_membership_income_start, 0)) * 100;
        v_room_growth := ((v_room_income_end - v_room_income_start) / NULLIF(v_room_income_start, 0)) * 100;
        v_fine_growth := ((v_fine_income_end - v_fine_income_start) / NULLIF(v_fine_income_start, 0)) * 100;
        
        -- Determine primary income source for yearly report
        IF v_membership_income_end >= v_room_income_end AND v_membership_income_end >= v_fine_income_end THEN
            v_top_source := 'Membership Renewals';
        ELSIF v_room_income_end >= v_membership_income_end AND v_room_income_end >= v_fine_income_end THEN
            v_top_source := 'Room Reservations';
        ELSE
            v_top_source := 'Fine Collections';
        END IF;
    ELSE
        -- Quarterly growth calculations (compare with previous year's same quarter)
        v_membership_growth := ((v_prev_membership_income - v_membership_income_q) / NULLIF(v_membership_income_q, 0)) * 100;
        v_room_growth := ((v_prev_room_income - v_room_income_q) / NULLIF(v_room_income_q, 0)) * 100;
        v_fine_growth := ((v_prev_fine_income - v_fine_income_q) / NULLIF(v_fine_income_q, 0)) * 100;
        
        -- Determine primary income source for quarterly report
        IF v_membership_income_q >= v_room_income_q AND v_membership_income_q >= v_fine_income_q THEN
            v_top_source := 'Membership Renewals';
        ELSIF v_room_income_q >= v_membership_income_q AND v_room_income_q >= v_fine_income_q THEN
            v_top_source := 'Room Reservations';
        ELSE
            v_top_source := 'Fine Collections';
        END IF;
    END IF;
    
    -- Overall growth indicator (updated to handle quarterly data properly)
    IF v_quarter IS NULL OR v_quarter = 0 THEN
        v_growth_indicator := get_trend_indicator(v_total_income, v_prev_total_income);
    ELSE
        v_growth_indicator := get_trend_indicator(v_total_income, v_prev_total_income);
    END IF;
    -- Output analysis with the correctly calculated values
    DBMS_OUTPUT.PUT_LINE('Analysis Summary:');
    DBMS_OUTPUT.PUT_LINE('  - Primary Income Source: ' || v_top_source || 
                       ' (' || format_trend(
                                 CASE 
                                   WHEN v_top_source = 'Membership Renewals' THEN 
                                        v_membership_percentage
                                   WHEN v_top_source = 'Room Reservations' THEN 
                                       v_room_percentage
                                   ELSE 
                                       v_fine_percentage
                                 END) || ' of total income)');

    DBMS_OUTPUT.PUT_LINE('  - Overall Trend: ' || v_growth_indicator);

    -- Provide insights based on the correct data
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Key Insights:');

    -- Membership insights using the proper growth calculation
    IF ABS(v_membership_growth) > 0 THEN
        IF v_membership_growth > 10 THEN
            DBMS_OUTPUT.PUT_LINE('  - Strong growth in membership renewals (' || format_trend(v_membership_growth) || ')');
        ELSIF v_membership_growth < -10 THEN
            DBMS_OUTPUT.PUT_LINE('  - Significant decline in membership renewals (' || format_trend(v_membership_growth) || ')');
            DBMS_OUTPUT.PUT_LINE('    RECOMMENDATION: Review membership benefits and marketing strategies');
        END IF;
    END IF;
    
    -- Room insights
    IF ABS(v_room_growth) > 0 THEN
        IF v_room_growth > 10 THEN
            DBMS_OUTPUT.PUT_LINE('  - Strong growth in room reservations (' || format_trend(v_room_growth) || ')');
        ELSIF v_room_growth < -10 THEN
            DBMS_OUTPUT.PUT_LINE('  - Significant decline in room reservations (' || format_trend(v_room_growth) || ')');
            DBMS_OUTPUT.PUT_LINE('    RECOMMENDATION: Evaluate room facilities and booking process');
        END IF;
    END IF;
    
    -- Fine insights
    IF ABS(v_fine_growth) > 0 THEN
        IF v_fine_growth > 10 THEN
            DBMS_OUTPUT.PUT_LINE('  - Significant increase in fine collections (' || format_trend(v_fine_growth) || ')');
            DBMS_OUTPUT.PUT_LINE('    NOTE: While this increases revenue, it may indicate issues with return compliance');
        ELSIF v_fine_growth < -10 THEN
            DBMS_OUTPUT.PUT_LINE('  - Substantial decrease in fine collections (' || format_trend(v_fine_growth) || ')');
            DBMS_OUTPUT.PUT_LINE('    NOTE: This may indicate improved return compliance');
        END IF;
    END IF;
    
    -- Add overall recommendation based on overall trend
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Overall Recommendation:');
    IF v_total_income > v_prev_total_income THEN
        DBMS_OUTPUT.PUT_LINE('  - Continue current strategies while focusing on further improving ' || 
                           CASE 
                             WHEN v_quarter IS NULL THEN
                                 CASE
                                     WHEN v_membership_percentage < 30 THEN 'membership engagement'
                                     WHEN v_room_percentage < 30 THEN 'room utilization'
                                     ELSE 'overall service quality'
                                 END
                             ELSE
                                 CASE
                                     WHEN (v_membership_income_q / NULLIF(v_total_income_q, 0)) * 100 < 30 THEN 'membership engagement'
                                     WHEN (v_room_income_q / NULLIF(v_total_income_q, 0)) * 100 < 30 THEN 'room utilization'
                                     ELSE 'overall service quality'
                                 END
                           END);
    ELSE
        DBMS_OUTPUT.PUT_LINE('  - Review pricing strategies and service quality for ' || 
                           CASE 
                             WHEN v_quarter IS NULL THEN
                                 CASE 
                                     WHEN v_membership_growth < -5 THEN 'membership plans'
                                     WHEN v_room_growth < -5 THEN 'room reservations'
                                     ELSE 'all income streams'
                                 END
                             ELSE
                                 CASE 
                                     WHEN v_membership_growth < -5 THEN 'membership plans'
                                     WHEN v_room_growth < -5 THEN 'room reservations'
                                     ELSE 'all income streams'
                                 END
                           END);
    END IF;
END generate_income_breakdown;

BEGIN
    -- Validate quarter if provided
    IF v_quarter IS NOT NULL THEN
        IF v_quarter NOT BETWEEN 0 AND 4 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Quarter must be between 0 and 4 or NULL');
        END IF;
    END IF;

    -- Get report ID from sequence
    SELECT LIBRARY_REPORT_SEQ.NEXTVAL INTO v_report_id FROM DUAL;
    
    -- Print report header
    print_header('LIBRARY MANAGEMENT SYSTEM - INCOME REPORT');
    DBMS_OUTPUT.PUT_LINE('Report Period: ' || 
                   CASE 
                     WHEN v_quarter IS NOT NULL AND v_quarter != 0 THEN 
                       'Q' || v_quarter || ' ' || v_start_year ||
                       CASE WHEN v_end_year != v_start_year 
                            THEN ' - ' || v_end_year 
                            ELSE '' 
                       END
                     ELSE 
                       CASE WHEN v_start_year = v_end_year 
                            THEN TO_CHAR(v_start_year)
                            ELSE v_start_year || ' - ' || v_end_year
                       END
                   END);
    
    -- Load all data
    load_income_data;
    load_yearly_data;
    load_quarterly_data;
    calculate_growth_rates;
    
    -- Generate report sections
    generate_yearly_report;
    generate_income_breakdown;
    
    -- Print footer
    print_footer;
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error generating report: ' || SQLERRM);
        ROLLBACK;
END LIBRARY_INCOME_REPORT;
/

-- PL/SQL block to execute the procedure
BEGIN
  DECLARE
    v_start_year NUMBER;
    v_end_year NUMBER;
    v_quarter NUMBER; 
  BEGIN
    -- Convert inputs to numbers
    v_start_year := TO_NUMBER('&startYearInput');
    v_end_year := TO_NUMBER('&endYearInput');
    v_quarter := TO_NUMBER('&quarterInput');
    
    -- Validate start year
    IF v_start_year IS NULL THEN 
        RAISE_APPLICATION_ERROR(-20001, 'Start year cannot be null. Please enter a valid start year.');
    ELSIF v_start_year = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Start year cannot be zero. Please enter a valid start year.');
    ELSIF v_start_year < 2020 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Start year must be 2020 or later. You entered: ' || v_start_year);
    ELSIF v_start_year > EXTRACT(YEAR FROM SYSDATE) + 5 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Start year cannot be more than 5 years in the future. You entered: ' || v_start_year);
    END IF;

    -- Validate end year
    IF v_end_year IS NULL THEN
        RAISE_APPLICATION_ERROR(-20005, 'End year cannot be null. Please enter a valid end year.');
    ELSIF v_end_year = 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'End year cannot be zero. Please enter a valid end year.');
    ELSIF v_end_year < v_start_year THEN
        RAISE_APPLICATION_ERROR(-20007, 'End year must be equal to or greater than start year. ' || 
                                      'Start: ' || v_start_year || ', End: ' || v_end_year);
    ELSIF v_end_year > EXTRACT(YEAR FROM SYSDATE) + 5 THEN
        RAISE_APPLICATION_ERROR(-20008, 'End year cannot be more than 5 years in the future. You entered: ' || v_end_year);
    END IF;

    -- Validate year order
    IF v_start_year > v_end_year THEN
      RAISE_APPLICATION_ERROR(-20002, 'Start year must be before end year');
    END IF;
    
      -- Validate quarter value if provided
    IF v_quarter NOT BETWEEN 0 AND 4 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Quarter must be between 0 and 4');
    END IF;
    
    -- Execute the report procedure
    LIBRARY_INCOME_REPORT(
      v_start_year,
      v_end_year,
      v_quarter  -- Will be NULL if quarter not provided
    );
    
  EXCEPTION
    WHEN VALUE_ERROR THEN
      DBMS_OUTPUT.PUT_LINE('Error: Please enter valid numbers for year and quarter');
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
  END;
END;
/