# Library Management System (Oracle SQL)

This project is a comprehensive Library Management System implemented using Oracle SQL. It includes table creation scripts, stored procedures, triggers, and reports for managing fines, reservations, income tracking, and fine waiver usage.

## 🗂️ Features

- User and Membership Management
- Business rules for applying vouchers and reserving books
- Book Inventory Checking
- Fine and Discount Campaign System
- Trigger-Based Validation and Logging
- Analytical Reports (e.g. Yearly Fine Reports)

## 🛠️ Technologies Used

- Oracle Database
- PL/SQL (Procedures, Triggers, Packages)

## 📁 File Structure

- `schema/`     – SQL scripts for creating and dropping tables
- `procedures/` – Stored procedures (e.g., `ApplyFineWaiverCampaign`)
- `triggers/`   – Compound and simple triggers
- `reports/`    – Analytical reports (e.g., `YearlyFineCollectionReport`)

## 🧪 How to Run

1. Install Oracle Database (latest version recommended).
2. Open SQL*Plus or Oracle SQL Developer.
3. Run scripts in the following order:
   - `schema/dropTables.sql`
   - `schema/createTables.sql`
   - `schema/insertData.sql`
   - `procedures/*.sql`
   - `triggers/*.sql`
   - `reports/*.sql`
4. Run test procedures like:

```sql
EXEC ApplyVoucher(fineId, voucherId, paymentMethod);
EXEC GenerateBookInsights(BookISBNCode, startData, endDate);
