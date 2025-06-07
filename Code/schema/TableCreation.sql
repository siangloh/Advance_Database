ALTER SESSION SET NLS_DATE_FORMAT = 'DD/MM/YYYY';
SET LINESIZE 200 
-- ensures the output fits on a single line
SET PAGESIZE 100 
-- Prevents any page breaks between rows
SET TRIMSPOOL ON 
-- Removes unnecessary spaces in the output

CREATE TABLE Parent(
    parentId CHAR(10) PRIMARY KEY NOT NULL,
    parentName VARCHAR2(50) NOT NULL UNIQUE,
    icNumber VARCHAR2(14) NOT NULL UNIQUE CHECK (REGEXP_LIKE(icNumber, '^[0-9]{6}[-]?[0-9]{2}[-]?[0-9]{4}$')),
    phoneNumber VARCHAR2(15) DEFAULT NULL UNIQUE CHECK (REGEXP_LIKE(phoneNumber, '^01[0-9]{1}[-]?[0-9]{7,8}$')),
    relationship VARCHAR2(15) NOT NULL CHECK (UPPER(relationship) IN ('FATHER', 'MOTHER', 'GUARDIAN', 'GRANDFATHER', 'GRANDMOTHER'))
);

CREATE TABLE "User" (
    userId CHAR(9) PRIMARY KEY NOT NULL,
    parentId CHAR(10) DEFAULT NULL,
    username VARCHAR2(50) NOT NULL,
    icNumber VARCHAR2(14) NOT NULL UNIQUE CHECK (REGEXP_LIKE(icNumber, '^[0-9]{6}[-]?[0-9]{2}[-]?[0-9]{4}$')),
    dob DATE GENERATED ALWAYS AS (
        CASE
            WHEN SUBSTR(icNumber, 1, 2) <= '49' 
            THEN TO_DATE('20' || SUBSTR(icNumber, 1, 2) || SUBSTR(icNumber, 3, 2) || SUBSTR(icNumber, 5, 2), 'YYYYMMDD')
        ELSE 
            TO_DATE('19' || SUBSTR(icNumber, 1, 2) || SUBSTR(icNumber, 3, 2) || SUBSTR(icNumber, 5, 2), 'YYYYMMDD')
        END
        ) VIRTUAL,
    phoneNumber VARCHAR2(15) DEFAULT NULL UNIQUE CHECK (REGEXP_LIKE(phoneNumber, '^01[0-9]{1}[-]?[0-9]{7,8}$')),
    role VARCHAR2(10) NOT NULL CHECK (UPPER(role) IN ('MEMBER', 'MANAGER', 'STAFF')),
    registerDate DATE DEFAULT CURRENT_DATE NOT NULL, 
    CONSTRAINT FK_USERPARENT FOREIGN KEY (parentId) REFERENCES Parent(parentId) ON DELETE SET NULL
);

CREATE TABLE Genre (
    genreId CHAR(5) PRIMARY KEY NOT NULL,
    genreName VARCHAR2(50) NOT NULL UNIQUE,
    dateCreated DATE DEFAULT CURRENT_DATE NOT NULL
);

CREATE TABLE Author (
    authorId CHAR(5) PRIMARY KEY NOT NULL,
    authorName VARCHAR2(50) NOT NULL,
    dob DATE DEFAULT NULL CHECK (dob IS NULL OR dob >= TO_DATE('01/01/1900', 'DD/MM/YYYY'))
);


CREATE TABLE Publisher (
    publisherId CHAR(5) PRIMARY KEY NOT NULL,
    publisherName VARCHAR2(50) NOT NULL,
    phoneNumber VARCHAR2(15) DEFAULT NULL UNIQUE CHECK (REGEXP_LIKE(phoneNumber, '^01[0-9]{1}[-]?[0-9]{7,8}$'))
);

CREATE TABLE Book(
    bookId CHAR(9) PRIMARY KEY NOT NULL,
    title VARCHAR2(100) NOT NULL,
    bookPages INT CHECK (bookPages > 0 AND bookPages <= 21540) NOT NULL,
    price DECIMAL(5,2) NOT NULL CHECK (price >= 0 AND price <= 136667300)
);

CREATE TABLE BookOfCopies(
    copyId INT GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1) PRIMARY KEY,
    bookId CHAR(9) NOT NULL,
    copyNumber INT NOT NULL,
    status VARCHAR(20) CHECK (UPPER(status) IN ('AVAILABLE', 'BROKEN', 'BORROWED', 'LOST')),
    dateCreated DATE DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT FK_BOOKCOPYBOOKS FOREIGN KEY (bookId) REFERENCES Book(bookId) ON DELETE CASCADE
);

CREATE TABLE ISBN (
    isbnId CHAR(17) PRIMARY KEY NOT NULL CHECK (REGEXP_LIKE(isbnId, '^97[89]-[0-9]-[0-9]{2}-[0-9]{6}-[0-9]$')),
    bookId CHAR(9) NOT NULL,
    publisherId CHAR(5) NOT NULL,
    publicationYear NUMBER(4) NOT NULL CHECK (publicationYear >= 1500),
    CONSTRAINT FK_ISBNBOOK FOREIGN KEY (bookId) REFERENCES Book(bookId) ON DELETE CASCADE,
    CONSTRAINT FK_ISBNPUBLISHER FOREIGN KEY (publisherId) REFERENCES Publisher(publisherId) ON DELETE CASCADE
);


CREATE TABLE BookAuthor(
    bookId CHAR(9) NOT NULL,
    authorId CHAR(5) NOT NULL,
    PRIMARY KEY (bookId, authorId),
    FOREIGN KEY (bookId) REFERENCES Book(bookId) ON DELETE CASCADE,
    FOREIGN KEY (authorId) REFERENCES Author(authorId) ON DELETE CASCADE
);

CREATE TABLE BookGenre (
    bookId CHAR(9) NOT NULL,
    genreId CHAR(5) NOT NULL,
    PRIMARY KEY (bookId, genreId),
    FOREIGN KEY (bookId) REFERENCES Book(bookId) ON DELETE CASCADE,
    FOREIGN KEY (genreId) REFERENCES Genre(genreId) ON DELETE CASCADE
);

CREATE TABLE Borrowing (
    borrowId CHAR(10) PRIMARY KEY NOT NULL,
    userId CHAR(9) NOT NULL,
    dateBorrow DATE DEFAULT CURRENT_DATE NOT NULL,
    status VARCHAR2(9) NOT NULL CHECK (UPPER(status) IN ('RESERVED', 'BORROWED', 'RETURNED', 'OVERDUE', 'CANCELLED', 'RBORROWED', 'REJECTED')),
    dueDate DATE GENERATED ALWAYS AS (dateBorrow + INTERVAL '10' DAY) VIRTUAL NOT NULL,
    CONSTRAINT FK_BORROWINGUSER FOREIGN KEY (userId) REFERENCES "User"(userId) ON DELETE CASCADE
);


CREATE TABLE BorrowingBooks(
    borrowId CHAR(10) NOT NULL,
    copyId INT NOT NULL,
    dateReturn DATE DEFAULT NULL,
    PRIMARY KEY (borrowId, copyId),
    CONSTRAINT FK_BORROWINGBOOKBRR FOREIGN KEY (borrowId) REFERENCES Borrowing(borrowId) ON DELETE CASCADE,
    CONSTRAINT FK_BORROWINGBOOKCOPY FOREIGN KEY (copyId) REFERENCES BookOfCopies(copyId) ON DELETE CASCADE
); 

CREATE TABLE Discount (
    discountId CHAR(9) PRIMARY KEY NOT NULL,
    discountValue DECIMAL(10,2) NOT NULL, 
    isPercentage NUMBER(1) NOT NULL,
    maxUsagePerUser INT DEFAULT NULL,
    minimumOrderValue DECIMAL(10,2) NOT NULL, 
    maxDiscountAmount DECIMAL(10,2) DEFAULT NULL, 
    dateCreated DATE DEFAULT CURRENT_DATE	
);


CREATE TABLE Voucher(
    voucherId CHAR(15) PRIMARY KEY NOT NULL,
    discountId CHAR(9) NOT NULL,
    voucherName VARCHAR2(50) NOT NULL UNIQUE,
    description VARCHAR2(255) DEFAULT NULL,
    isMember NUMBER(1) NOT NULL,
    status VARCHAR2(9) NOT NULL CHECK(UPPER(status) IN ('ACTIVE', 'NONACTIVE')),
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
    CONSTRAINT FK_VOUCHERDISCOUNT FOREIGN KEY (discountId) REFERENCES Discount(discountId) ON DELETE CASCADE
);

CREATE TABLE Fine (
    fineId CHAR(9) PRIMARY KEY NOT NULL,
    borrowId CHAR(10) NOT NULL,
    copyId INT NOT NULL,
    voucherId CHAR(15) DEFAULT NULL,
    paymentDate DATE DEFAULT NULL,
    fineAmount NUMBER(10,2) NOT NULL CHECK (fineAmount >= 0.0),
    discountApplied NUMBER(10,2) DEFAULT 0.0 CHECK (discountApplied >= 0.0),
    sst NUMBER(10,2) GENERATED ALWAYS AS ((fineAmount - discountApplied) * 0.10) VIRTUAL,
    adminFee NUMBER(10,2) DEFAULT 0.0 NOT NULL CHECK(adminFee >= 0.0),
    finalAmount NUMBER(10,2) GENERATED ALWAYS AS (fineAmount - discountApplied + ((fineAmount - discountApplied) * 0.10) + adminFee) VIRTUAL,
    status VARCHAR2(7) CHECK (UPPER(status) IN ('PAID', 'UNPAID')) NOT NULL,
    CONSTRAINT FK_FINEBORROW FOREIGN KEY (borrowId) REFERENCES Borrowing(borrowId) ON DELETE CASCADE,
    CONSTRAINT FK_FINEBOOKCOPIES FOREIGN KEY (copyId) REFERENCES BookOfCopies(copyId) ON DELETE CASCADE,
    CONSTRAINT FK_FINEFNVOUCHER FOREIGN KEY (voucherId) REFERENCES Voucher(voucherId) ON DELETE CASCADE
);

CREATE TABLE MembershipPlan (
    planId VARCHAR2(5) PRIMARY KEY NOT NULL CHECK (planId LIKE 'MP%'),
    planName VARCHAR2(20) NOT NULL,
    durationInMonth NUMBER(4,2) NOT NULL CHECK (durationInMonth > 0),
    price NUMBER(5,2) NOT NULL CHECK (price > 0),
    description VARCHAR2(100) NOT NULL,
    dateCreated DATE DEFAULT CURRENT_DATE NOT NULL
);

CREATE TABLE Membership (
    membershipId CHAR(9) PRIMARY KEY NOT NULL CHECK (membershipId LIKE 'M%'),
    userId CHAR(9) NOT NULL,
    status VARCHAR2(10) NOT NULL CHECK (UPPER(status) IN ('ACTIVE', 'EXPIRED')),
    endDate DATE NOT NULL,
    CONSTRAINT FK_MEMBERSHIPUSER FOREIGN KEY (userId) REFERENCES "User"(userId)
);

CREATE TABLE Renewal (
    renewalId CHAR(9) PRIMARY KEY NOT NULL CHECK (renewalId LIKE 'R%'),
    membershipId CHAR(9) NOT NULL,
    planId VARCHAR2(5) NOT NULL,
    renewalDate DATE NOT NULL,
    oldEndDate DATE NOT NULL,
    newEndDate DATE NOT NULL,
    totalAmount NUMBER(10,2) NOT NULL CHECK(totalAmount >= 0),
    discountApplied NUMBER(10,2) DEFAULT 0.0 CHECK (discountApplied >= 0.0),
    sst NUMBER(10,2) GENERATED ALWAYS AS ((totalAmount- discountApplied) * 0.10) VIRTUAL,
    finalAmount NUMBER(10,2) GENERATED ALWAYS AS (totalAmount - discountApplied + ((totalAmount - discountApplied) * 0.10)) VIRTUAL,
    CONSTRAINT FK_RENEWALMEM FOREIGN KEY (membershipId) REFERENCES Membership(membershipId),
    CONSTRAINT FK_RENEWALPLAN FOREIGN KEY (planId) REFERENCES MembershipPlan(planId),
    CONSTRAINT chk_renewal_dates CHECK (newEndDate > oldEndDate)
);

CREATE TABLE RoomType (
    roomTypeId VARCHAR2(6) PRIMARY KEY NOT NULL CHECK (roomTypeId LIKE 'RT%'),
    roomTypeName VARCHAR2(100) NOT NULL,
    description VARCHAR2(200) NOT NULL,
    capacity NUMBER(3) NOT NULL CHECK (capacity > 0),
    pricePerHour NUMBER(5,2) NOT NULL CHECK (pricePerHour >= 0)
);

CREATE TABLE Room (
    roomId CHAR(10) PRIMARY KEY NOT NULL CHECK (roomId LIKE 'RM%'),
    roomTypeId CHAR(6) NOT NULL,
    roomName VARCHAR2(50) NOT NULL,
    status VARCHAR2(15) NOT NULL CHECK (UPPER(status) IN ('AVAILABLE', 'MAINTENANCE', 'RESERVED'))
);

CREATE TABLE RoomReservation (
    reserveId CHAR(10) PRIMARY KEY NOT NULL CHECK (reserveId LIKE 'RR%'),
    roomId CHAR(10) NOT NULL,
    userId CHAR(9) NOT NULL,
    voucherId CHAR(15) DEFAULT NULL,
    reserveDateTime TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    duration NUMBER(2) NOT NULL CHECK (duration > 0),
    totalAmount NUMBER(10,2) NOT NULL CHECK(totalAmount >= 0),
    discountApplied NUMBER(10,2) DEFAULT 0.0 CHECK (discountApplied >= 0.0),
    sst NUMBER(10,2) GENERATED ALWAYS AS ((totalAmount- discountApplied) * 0.10) VIRTUAL,
    finalAmount NUMBER(10,2) GENERATED ALWAYS AS (totalAmount - discountApplied + ((totalAmount - discountApplied) * 0.10)) VIRTUAL,
    status VARCHAR2(10) NOT NULL CHECK(UPPER(status) IN ('RESERVED', 'ONGOING', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT FK_ROOMRESERVATIONROOM FOREIGN KEY (roomId) REFERENCES Room(roomId),
    CONSTRAINT FK_ROOMRESERVATIONUSER FOREIGN KEY (userId) REFERENCES "User"(userId),
    CONSTRAINT FK_ROOMRESERVATIONVOUCHER FOREIGN KEY (voucherId) REFERENCES Voucher(voucherId)
);

CREATE TABLE Transaction (
  transactionId CHAR(9) PRIMARY KEY NOT NULL,
  fineId CHAR(9) DEFAULT NULL,
  renewalId CHAR(9) DEFAULT NULL,
  reserveId CHAR(10) DEFAULT NULL,
  transactionDate DATE DEFAULT CURRENT_DATE,
  transactionMethod VARCHAR2(20) NOT NULL CHECK (UPPER(transactionMethod) IN ('CASH', 'CREDIT CARD', 'DEBIT CARD', 'PAYPAL', 'BANK TRANSFER', 'TNG')),
  amount DECIMAL(10,2) NOT NULL CHECK(amount >= 0.0),
  CONSTRAINT FK_TRANSACTIONFINE FOREIGN KEY (fineId) REFERENCES Fine(fineId) ON DELETE CASCADE,
  CONSTRAINT FK_TRANSACTIONRENEWAL FOREIGN KEY (renewalId) REFERENCES Renewal(renewalId) ON DELETE CASCADE,
  CONSTRAINT FK_TRANSACTIONRESERVE FOREIGN KEY (reserveId) REFERENCES RoomReservation(reserveId) ON DELETE CASCADE
);

CREATE TABLE Invoice (
    invoiceId CHAR(9) PRIMARY KEY NOT NULL,
    transactionId CHAR(9) NOT NULL,
    invoiceDate DATE DEFAULT CURRENT_DATE,
    remarks VARCHAR2(255) DEFAULT NULL,
    overdueDays INT NOT NULL CHECK (overdueDays >= 0),
    CONSTRAINT FK_INVOICETRANSACTION FOREIGN KEY (transactionId) REFERENCES Transaction(transactionId) ON DELETE CASCADE
);

CREATE TABLE Feedback(
    feedbackId CHAR(10) PRIMARY KEY NOT NULL,
    userId CHAR(9) NOT NULL,
    bookId CHAR(9) NOT NULL,
    reviewComment VARCHAR2(255) DEFAULT NULL, 
    rating INT NOT NULL CHECK(rating > 0 AND rating <= 5),
    feedbackDate DATE DEFAULT CURRENT_DATE,
    CONSTRAINT FK_FEEDBACKUSER FOREIGN KEY(userId) REFERENCES "User"(userId) ON DELETE CASCADE,
    CONSTRAINT FK_FEEDBACKBOOK FOREIGN KEY(bookId) REFERENCES Book(bookId) ON DELETE CASCADE
);

CREATE TABLE Email(
    emailId CHAR(9) PRIMARY KEY NOT NULL,
    userId CHAR(9) DEFAULT NULL,
    parentId CHAR(10) DEFAULT NULL,
    authorId CHAR(5) DEFAULT NULL,
    publisherId CHAR(5) DEFAULT NULL,
    emailAddress VARCHAR2(50) NOT NULL CHECK (REGEXP_LIKE(emailAddress, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.com$')),
    emailType VARCHAR2(10) NOT NULL,
    CONSTRAINT FK_EMAILPUBLISHER FOREIGN KEY (publisherId) REFERENCES Publisher(publisherId) ON DELETE SET NULL,
    CONSTRAINT FK_EMAILAUTHOR FOREIGN KEY (authorId) REFERENCES Author(authorId) ON DELETE SET NULL,
    CONSTRAINT FK_EMAILUSER FOREIGN KEY (userId) REFERENCES "User"(userId) ON DELETE SET NULL,
    CONSTRAINT FK_EMAILPARENT FOREIGN KEY (parentId) REFERENCES Parent(parentId) ON DELETE SET NULL
);

CREATE TABLE Address(
    addressId CHAR(10) PRIMARY KEY NOT NULL,
    userId CHAR(9) DEFAULT NULL,
    parentId CHAR(10) DEFAULT NULL,
    authorId CHAR(5) DEFAULT NULL,
    publisherId CHAR(5) DEFAULT NULL,
    line1 VARCHAR2(50) NOT NULL CHECK (REGEXP_LIKE(line1, '^[A-Za-z0-9 ,.-]+$')),
    line2 VARCHAR2(50) DEFAULT NULL CHECK (line2 IS NULL OR REGEXP_LIKE(line2, '^[A-Za-z0-9 ,.-]+$')),
    postcode CHAR(5) NOT NULL CHECK (REGEXP_LIKE(postcode, '^[0-9]{5}$') AND postcode != '00000'),
    city VARCHAR2(15) NOT NULL,
    state VARCHAR2(15) NOT NULL CHECK (UPPER(state) IN ('JOHOR', 'KEDAH', 'KELANTAN', 'MELAKA', 
    'NEGERI SEMBILAN', 'PAHANG', 'PULAU PINANG', 'PERAK', 'PERLIS', 
    'SABAH', 'SARAWAK', 'SELANGOR', 'TERENGGANU', 'KUALA LUMPUR', 
    'PUTRAJAYA', 'LABUAN')),
    country VARCHAR2(10) DEFAULT 'Malaysia' NOT NULL,
    CONSTRAINT FK_ADDRESSPUBLISHER FOREIGN KEY (publisherId) REFERENCES Publisher(publisherId) ON DELETE SET NULL,
    CONSTRAINT FK_ADDRESSAUTHOR FOREIGN KEY (authorId) REFERENCES Author(authorId) ON DELETE SET NULL,
    CONSTRAINT FK_ADDRESSUSER FOREIGN KEY (userId) REFERENCES "User"(userId) ON DELETE SET NULL,
    CONSTRAINT FK_ADDRESSPARENT FOREIGN KEY (parentId) REFERENCES Parent(parentId) ON DELETE SET NULL
);


