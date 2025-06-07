# Library Management System (Oracle SQL)

This project is a comprehensive Library Management System implemented using Oracle SQL. It includes table creation scripts, stored procedures, triggers, and reports for managing books, members, fines, campaigns, and more.

## 🗂️ Features

- User and Membership Management
- Book Inventory Management
- Fine and Discount Campaign System
- Trigger-Based Validation and Logging
- Analytical Reports (e.g. Yearly Fine Reports)

## 🛠️ Technologies Used

- Oracle Database
- PL/SQL (Procedures, Triggers, Packages)

## 📁 File Structure

- `schema/` - SQL scripts for creating tables and constraints
- `procedures/` - Stored procedures (e.g. ApplyFineWaiverCampaign)
- `triggers/` - Compound and simple triggers
- `reports/` - Analytical reports (e.g. YearlyFineCollectionReport)

## 🧪 How to Run

1. Install Oracle Database (version XX or higher).
2. Open SQL*Plus or Oracle SQL Developer.
3. Run scripts in this order:
   - `schema/create_tables.sql`
   - `schema/insert_sample_data.sql`
   - `procedures/*.sql`
   - `triggers/*.sql`
4. Run test queries or call procedures like:

```sql
EXEC ApplyFineWaiverCampaign('F00010225');
EXEC YearlyFineCollectionReport(2024);
