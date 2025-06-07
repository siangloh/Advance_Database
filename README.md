# Library Management System (Oracle SQL)

This project is a comprehensive Library Management System implemented using Oracle SQL. It includes table creation scripts, stored procedures, triggers, and reports for fine, reservatop, income, and fine waiver usage.

## 🗂️ Features

- User and Membership Management
- Specific rules for apply voucher and reserve book
- Book Inventory Checking
- Fine and Discount Campaign System
- Trigger-Based Validation and Logging
- Analytical Reports (e.g. Yearly Fine Reports)

## 🛠️ Technologies Used

- Oracle Database
- PL/SQL (Procedures, Triggers, Packages)

## 📁 File Structure

- `schema/`     - SQL scripts for creating tables and constraints
- `procedures/` - Stored procedures (e.g. ApplyFineWaiverCampaign)
- `triggers/`   - Compound and simple triggers
- `reports/`    - Analytical reports (e.g. YearlyFineCollectionReport)

## 🧪 How to Run

1. Install Oracle SQL (preferred using latest version).
2. Open SQL*Plus or Oracle SQL Developer.
3. Run scripts in this order:
   -`schema/tableDeletion.sql`
   - `schema/tableInsertion.sql`
   - `schema/dataInsertion.sql`
   - `procedures/*.sql`
   - `triggers/*.sql`
   - `reports/*.sql`
4. Run test queries or call procedures like:

```sql
EXEC ApplyFineWaiverCampaign('F00010225');
EXEC YearlyFineCollectionReport(2024);
