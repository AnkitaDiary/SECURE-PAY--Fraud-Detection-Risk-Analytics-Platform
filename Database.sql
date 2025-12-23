-- ===============================================
-- 1️⃣ Create Database
-- ===============================================
CREATE DATABASE IF NOT EXISTS credit_card_database;
USE credit_card_database;

-- ===============================================
-- 2️⃣ Staging Table (Raw Dataset)
-- ===============================================
CREATE TABLE IF NOT EXISTS transactions_staging (
    raw_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_id      VARCHAR(100),
    customer_id         VARCHAR(50),
    customer_name       VARCHAR(255),
    customer_state      VARCHAR(100),
    transaction_date    VARCHAR(100),
    transaction_amount  DECIMAL(12,2),
    transaction_category VARCHAR(100),
    card_type           VARCHAR(50),
    bank_id             VARCHAR(50),
    bank_name           VARCHAR(255),
    merchant_id         VARCHAR(50),
    merchant_name       VARCHAR(255),
    merchant_location   VARCHAR(255),
    is_fraud            TINYINT,
    fraud_score         DECIMAL(7,2),
    fraud_risk_correct  VARCHAR(20),
	transaction_hour    INT,            -- extracted hour (0-23) or NULL
    card_present        TINYINT,        -- 0 = No, 1 = Yes
    is_international    TINYINT         -- 0 = Domestic, 1 = International

);
select * from transactions_staging;
-- ===============================================
-- 3️⃣ Core Tables
-- ===============================================
CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_name VARCHAR(255) NOT NULL,
    customer_state VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS banks (
    bank_id VARCHAR(50) PRIMARY KEY,
    bank_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE (bank_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS merchants (
    merchant_id VARCHAR(50) NOT NULL,
    merchant_name VARCHAR(255) NOT NULL,
    merchant_state VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (merchant_id, merchant_state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id VARCHAR(100) PRIMARY KEY,
    customer_id VARCHAR(50) NOT NULL,
    bank_id VARCHAR(50),
    merchant_id VARCHAR(50) NOT NULL,
    merchant_state VARCHAR(100) NOT NULL,
    transaction_date DATE DEFAULT (CURRENT_DATE),
    transaction_amount DECIMAL(12,2) NOT NULL,
    transaction_category VARCHAR(100),
    card_type VARCHAR(50),
    transaction_hour INT,
    card_present TINYINT,
    is_international TINYINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (bank_id) REFERENCES banks(bank_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    FOREIGN KEY (merchant_id, merchant_state) REFERENCES merchants(merchant_id, merchant_state)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_transaction_date (transaction_date),
    UNIQUE (transaction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===============================================
-- ⭐ UPDATED PREDICTIONS TABLE (with new columns)
-- ===============================================
CREATE TABLE IF NOT EXISTS predictions (
    prediction_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(100) NOT NULL,
    is_fraud TINYINT,
    fraud_score DECIMAL(7,2),
    fraud_risk_correct VARCHAR(20),

 

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_is_fraud (is_fraud)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===============================================
-- 4️⃣ Load Data Into Core Tables
-- ===============================================

INSERT IGNORE INTO customers (customer_id, customer_name, customer_state)
SELECT DISTINCT TRIM(customer_id), TRIM(customer_name), TRIM(customer_state)
FROM transactions_staging;

INSERT IGNORE INTO banks (bank_id, bank_name)
SELECT DISTINCT TRIM(bank_id), TRIM(bank_name)
FROM transactions_staging;

INSERT IGNORE INTO merchants (merchant_id, merchant_name, merchant_state)
SELECT DISTINCT TRIM(merchant_id), TRIM(merchant_name), TRIM(merchant_location)
FROM transactions_staging;

INSERT INTO transactions (
    transaction_id, customer_id, bank_id, merchant_id, merchant_state,
    transaction_date, transaction_amount, transaction_category, card_type,transaction_hour,
    card_present,
    is_international
)
SELECT
    TRIM(transaction_id),
    TRIM(customer_id),
    TRIM(bank_id),
    TRIM(merchant_id),
    TRIM(merchant_location),
    CASE
        WHEN transaction_date LIKE '%/%'
            THEN STR_TO_DATE(transaction_date, '%m/%d/%Y')
        WHEN transaction_date LIKE '%-%'
            THEN STR_TO_DATE(transaction_date, '%d-%m-%Y')
        ELSE NULL
    END,
    transaction_amount,
    TRIM(transaction_category),
    TRIM(card_type),
    transaction_hour,
    card_present,
    is_international
FROM transactions_staging;

INSERT INTO predictions (
    transaction_id, is_fraud, fraud_score, fraud_risk_correct
)
SELECT
    TRIM(transaction_id),
    is_fraud,
    fraud_score,
    TRIM(fraud_risk_correct)
FROM transactions_staging
WHERE transaction_id IS NOT NULL
  AND transaction_id IN (SELECT transaction_id FROM transactions);
-- ===============================================
-- ⭐ UPDATED VIEW INCLUDING NEW COLUMNS
-- ===============================================
CREATE OR REPLACE VIEW vw_transactions_full AS
SELECT
    t.transaction_id,
    c.customer_id,
    c.customer_name,
    c.customer_state,
    t.transaction_date,
    t.transaction_amount,
    t.transaction_category,
    t.card_type,
    b.bank_id,
    b.bank_name,
    m.merchant_id,
    m.merchant_name,
    m.merchant_state,
    p.is_fraud,
    p.fraud_score,
    p.fraud_risk_correct,
    t.transaction_hour,
    t.card_present,
    t.is_international
FROM transactions t
LEFT JOIN customers c ON t.customer_id = c.customer_id
LEFT JOIN banks b ON t.bank_id = b.bank_id
LEFT JOIN merchants m ON t.merchant_id = m.merchant_id AND t.merchant_state = m.merchant_state
LEFT JOIN predictions p ON t.transaction_id = p.transaction_id
ORDER BY t.transaction_id;
select * from vw_transactions_full;
-- ===============================================
-- ⭐ UPDATED STORED PROCEDURE (with new columns)
-- ===============================================
DELIMITER $$

CREATE PROCEDURE add_new_transaction(
    IN p_customer_name VARCHAR(255),
    IN p_customer_state VARCHAR(100),
    IN p_bank_id VARCHAR(50),
    IN p_merchant_id VARCHAR(50),
    IN p_merchant_state VARCHAR(100),
    IN p_transaction_date DATETIME,
    IN p_transaction_amount DECIMAL(12,2),
    IN p_transaction_category VARCHAR(100),
    IN p_card_type VARCHAR(50),
    IN p_is_fraud TINYINT,
    IN p_fraud_score DECIMAL(7,2),
    IN p_fraud_risk_correct VARCHAR(20),

    -- ⭐ NEW INPUTS
    IN p_transaction_hour INT,
    IN p_card_present TINYINT,
    IN p_is_international TINYINT
)
BEGIN
    DECLARE v_customer_id VARCHAR(50);
    DECLARE v_transaction_id VARCHAR(100);

    -- Find or create customer
    SELECT customer_id INTO v_customer_id
    FROM customers
    WHERE LOWER(customer_name) = LOWER(p_customer_name)
      AND LOWER(customer_state) = LOWER(p_customer_state)
    LIMIT 1;

    IF v_customer_id IS NULL THEN
        SET v_customer_id = CONCAT('C', LPAD(FLOOR(RAND()*1000000),6,'0'));
        INSERT INTO customers(customer_id, customer_name, customer_state)
        VALUES(v_customer_id, p_customer_name, p_customer_state);
    END IF;

    -- Create new transaction_id
    SET v_transaction_id = CONCAT('T', LPAD(FLOOR(RAND()*1000000),6,'0'));

    -- Insert into transactions table
    INSERT INTO transactions (
        transaction_id, customer_id, bank_id, merchant_id, merchant_state,
        transaction_date, transaction_amount, transaction_category, card_type,
        transaction_hour, card_present, is_international
    )
    VALUES (
        v_transaction_id,
        v_customer_id,
        p_bank_id,
        p_merchant_id,
        p_merchant_state,
		CURDATE(),
        p_transaction_amount,
        p_transaction_category,
        p_card_type,
        p_transaction_hour,
        p_card_present,
        p_is_international
    );

    -- Insert into predictions (ONLY prediction fields)
    INSERT INTO predictions (
        transaction_id, is_fraud, fraud_score, fraud_risk_correct
    )
    VALUES (
        v_transaction_id,
        p_is_fraud,
        p_fraud_score,
        p_fraud_risk_correct
    );
END$$

DELIMITER ;

UPDATE transactions
SET transaction_date = CURDATE()
WHERE transaction_date IS NULL;





USE credit_card_database;

SELECT * 
FROM customers
WHERE customer_name = 'Anandita Rai';

SELECT * 
FROM vw_transactions_full
WHERE customer_name = 'Anika Mariam';



SHOW FULL TABLES WHERE TABLE_TYPE = 'VIEW';

-- Or check specifically
SELECT * FROM vw_transactions_full where customer_name= "Anandita Rai";



