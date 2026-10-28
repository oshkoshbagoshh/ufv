-- ============================================================
-- Unity of Fox Valley (UFV) — Bank Reconciliation Schema
-- Statement period: June 2026 | First State Bank
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. CHART OF ACCOUNTS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chart_of_accounts (
    id              SERIAL PRIMARY KEY,
    account_code    VARCHAR(20)  UNIQUE,
    account_name    VARCHAR(200) NOT NULL,
    account_type    VARCHAR(30)  NOT NULL,   -- Bank | Income | Expense | Asset | Liability | Equity | Non-Posting
    parent_id       INTEGER      REFERENCES chart_of_accounts(id),
    description     TEXT,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coa_parent ON chart_of_accounts(parent_id);
CREATE INDEX IF NOT EXISTS idx_coa_type   ON chart_of_accounts(account_type);

-- ────────────────────────────────────────────────────────────
-- 2. BANK ACCOUNTS  (links to COA)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bank_accounts (
    id                  SERIAL PRIMARY KEY,
    account_number_last4 CHAR(4)      NOT NULL,
    account_name        VARCHAR(100) NOT NULL,
    bank_name           VARCHAR(100) NOT NULL DEFAULT 'First State Bank',
    coa_account_id      INTEGER      REFERENCES chart_of_accounts(id),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ────────────────────────────────────────────────────────────
-- 3. STATEMENT PERIODS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS statement_periods (
    id                  SERIAL PRIMARY KEY,
    bank_account_id     INTEGER      NOT NULL REFERENCES bank_accounts(id),
    period_start        DATE         NOT NULL,
    period_end          DATE         NOT NULL,
    beginning_balance   NUMERIC(12,2) NOT NULL,
    ending_balance      NUMERIC(12,2) NOT NULL,
    total_credits       NUMERIC(12,2),
    total_debits        NUMERIC(12,2),
    interest_earned     NUMERIC(12,2),
    is_reconciled       BOOLEAN      NOT NULL DEFAULT FALSE,
    reconciled_at       TIMESTAMPTZ,
    UNIQUE (bank_account_id, period_end)
);

-- ────────────────────────────────────────────────────────────
-- 4. TRANSACTIONS  (raw from bank statement)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transactions (
    id                  SERIAL PRIMARY KEY,
    statement_period_id INTEGER      NOT NULL REFERENCES statement_periods(id),
    bank_account_id     INTEGER      NOT NULL REFERENCES bank_accounts(id),
    transaction_date    DATE         NOT NULL,
    description         TEXT         NOT NULL,          -- cleaned/display label
    raw_description     TEXT,                           -- verbatim from bank
    amount              NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    direction           VARCHAR(6)   NOT NULL CHECK (direction IN ('credit', 'debit')),
    transaction_type    VARCHAR(20)  NOT NULL,
        -- 'deposit' | 'electronic_credit' | 'other_credit'
        -- 'electronic_debit' | 'other_debit' | 'check'
    check_number        VARCHAR(10),
    is_coded            BOOLEAN      NOT NULL DEFAULT FALSE,
    notes               TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tx_date       ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_tx_period     ON transactions(statement_period_id);
CREATE INDEX IF NOT EXISTS idx_tx_account    ON transactions(bank_account_id);
CREATE INDEX IF NOT EXISTS idx_tx_uncoded    ON transactions(is_coded) WHERE is_coded = FALSE;

-- ────────────────────────────────────────────────────────────
-- 5. TRANSACTION CODINGS  (supports split coding)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transaction_codings (
    id              SERIAL PRIMARY KEY,
    transaction_id  INTEGER      NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    coa_account_id  INTEGER      NOT NULL REFERENCES chart_of_accounts(id),
    amount          NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    memo            TEXT,
    coded_by        VARCHAR(100),                       -- user/process that coded it
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coding_tx  ON transaction_codings(transaction_id);
CREATE INDEX IF NOT EXISTS idx_coding_coa ON transaction_codings(coa_account_id);

-- ────────────────────────────────────────────────────────────
-- HELPER: flag transaction coded when all splits sum to amount
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_is_coded() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE transactions t
    SET    is_coded = (
               SELECT COALESCE(SUM(c.amount),0) FROM transaction_codings c WHERE c.transaction_id = t.id
           ) >= t.amount
    WHERE  t.id = COALESCE(NEW.transaction_id, OLD.transaction_id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_sync_coded
AFTER INSERT OR UPDATE OR DELETE ON transaction_codings
FOR EACH ROW EXECUTE FUNCTION sync_is_coded();

-- ────────────────────────────────────────────────────────────
-- VIEWS
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_uncoded_transactions AS
SELECT
    t.id,
    ba.account_name,
    t.transaction_date,
    t.direction,
    t.amount,
    t.transaction_type,
    t.check_number,
    t.description,
    COALESCE(SUM(tc.amount), 0)          AS coded_amount,
    t.amount - COALESCE(SUM(tc.amount),0) AS remaining
FROM transactions t
JOIN bank_accounts ba ON ba.id = t.bank_account_id
LEFT JOIN transaction_codings tc ON tc.transaction_id = t.id
WHERE t.is_coded = FALSE
GROUP BY t.id, ba.account_name;

CREATE OR REPLACE VIEW v_period_summary AS
SELECT
    sp.period_end,
    ba.account_name,
    ba.account_number_last4,
    sp.beginning_balance,
    sp.ending_balance,
    sp.total_credits,
    sp.total_debits,
    sp.is_reconciled,
    COUNT(t.id)                           AS total_transactions,
    COUNT(t.id) FILTER (WHERE NOT t.is_coded) AS uncoded_count
FROM statement_periods sp
JOIN bank_accounts ba ON ba.id = sp.bank_account_id
LEFT JOIN transactions t ON t.statement_period_id = sp.id
GROUP BY sp.id, ba.account_name, ba.account_number_last4;

-- ============================================================
-- SEED DATA
-- ============================================================

-- ── Chart of Accounts (key accounts needed for June coding) ──
INSERT INTO chart_of_accounts (account_code, account_name, account_type, description) VALUES
  -- ASSETS / BANK
  ('100.000', 'General Fund Checking',             'Bank',    NULL),
  ('100.100', 'Reserved Funds Checking',           'Bank',    NULL),
  ('101.000', 'Petty Cash',                        'Bank',    'Cash on Hand'),
  ('100.201', 'Accounts Receivable',               'Asset',   NULL),
  ('100.250', 'Prepaid Expense',                   'Asset',   NULL),
  ('160.01',  'PayPal Clearing (Online)',           'Asset',   'Donations from PayPal'),
  -- INCOME PARENTS
  ('403.000', 'CLASSES',                           'Income',  NULL),
  ('405.000', 'EVENTS',                            'Income',  NULL),
  ('406.000', 'MINISTRY',                          'Income',  'Contribution Income'),
  ('407.000', 'SPECIAL FUNDS',                     'Income',  NULL),
  -- INCOME DETAIL
  ('406.111', 'Contributions Sunday Service',      'Income',  'Unrestricted Contributions'),
  ('406.112', 'Contributions-Mail In',             'Income',  NULL),
  ('406.115', 'Interest Income',                   'Income',  'Interest Income'),
  ('406.119', 'Interest Income RF',                'Income',  NULL),
  ('406.118', 'Tithe Payroll Deduction',           'Income',  NULL),
  ('405.106', 'Fund Raisers Income',               'Income',  NULL),
  ('405.112', 'Feasts/Hospitality',                'Income',  NULL),
  ('405.113', 'Essential Oils',                    'Income',  NULL),
  ('405.119', '50th Anniversary Income',           'Income',  'Income from 50th Anniversary Celebration'),
  ('407.602', 'Capital Improvements Reserve',      'Income',  NULL),
  ('407.603', 'Community Outreach/Inreach Fund',   'Income',  NULL),
  ('407.700', 'YOUTH EDUCATION',                   'Income',  NULL),
  ('407.727', 'Youth of Unity Income',             'Income',  NULL),
  -- EXPENSE PARENTS
  ('501.000', 'ADMINISTRATIVE EXPENSES',           'Expense', NULL),
  ('502.000', 'BUILDING & GROUNDS EXPENSE',        'Expense', 'Repairs and Maintenance'),
  ('502.500', 'Utilities & Telephone',             'Expense', NULL),
  ('503.000', 'CLASS EXPENSE',                     'Expense', NULL),
  ('504.000', 'COMPENSATION',                      'Expense', NULL),
  ('505.000', 'EVENTS EXPENSE',                    'Expense', NULL),
  ('506.000', 'MINISTRY EXPENSE & TITHE',          'Expense', NULL),
  ('507.000', 'SPECIAL FUNDS EXPENSE',             'Expense', NULL),
  -- EXPENSE DETAIL
  ('501.151', 'Advertising/Mktg Expense',          'Expense', NULL),
  ('501.153', 'Copier Expenses',                   'Expense', NULL),
  ('501.154', 'Computer/Software',                 'Expense', 'Office computers and software'),
  ('501.155', 'Office Supplies',                   'Expense', NULL),
  ('501.156', 'Postage and Mailing Expense',       'Expense', NULL),
  ('501.157', 'Printing Expense',                  'Expense', NULL),
  ('501.158', 'Staff/Bd Train/Functions/Expense',  'Expense', NULL),
  ('502.161', 'AlarmDetection/Sprinklers Exp',     'Expense', NULL),
  ('502.164', 'Housekeeping Expense',              'Expense', NULL),
  ('502.169', 'Insurance Expense',                 'Expense', 'Insurance'),
  ('502.174', 'Mortgage Principle',                'Expense', NULL),
  ('502.175', 'Utilities-Elec/Sewer/Water Exp',   'Expense', NULL),
  ('502.176', 'Utilities-Gas Expense',             'Expense', NULL),
  ('502.177', 'Utilities-Phone Expense',           'Expense', NULL),
  ('502.182', 'Capital Improvement Reserve',       'Expense', NULL),
  ('504.101', 'Gross Pay - Business Manager',      'Expense', NULL),
  ('504.102', 'Gross Pay - Music Director',        'Expense', NULL),
  ('504.106', 'Payroll Taxes',                     'Expense', NULL),
  ('504.112', 'Gross Salary - Senior Minister',    'Expense', NULL),
  ('504.113', 'Manse Expense',                     'Expense', NULL),
  ('504.115', 'Reimbursable Expense',              'Expense', NULL),
  ('505.106', 'Fund Raiser Expense',               'Expense', NULL),
  ('505.111', 'Workshop/Special Event Exp',        'Expense', NULL),
  ('505.113', 'Essential Oils Exp',                'Expense', NULL),
  ('506.201', 'Community Outreach Tithe',          'Expense', NULL),
  ('506.203', 'Ministry Tithe',                    'Expense', NULL),
  ('506.318', 'Hospitality Expense',               'Expense', NULL),
  ('506.319', 'Music Expense',                     'Expense', NULL),
  ('507.602', 'Capital Improvement Expense',       'Expense', NULL),
  ('507.603', 'Community Outreach/Inreach Exp',    'Expense', NULL),
  ('507.615', 'Audio Visual Expense',              'Expense', NULL),
  ('507.700', 'YOUTH EDUCATION EXPENSE',           'Expense', NULL),
  ('507.725', 'Children''s Church Education Exp',  'Expense', NULL),
  ('507.727', 'YOU Expenses',                      'Expense', NULL),
  ('66000',   'Payroll Expenses',                  'Expense', 'Payroll expenses'),
  ('66900',   'Reconciliation Discrepancies',      'Expense', 'Discrepancies between bank and records')
ON CONFLICT (account_code) DO NOTHING;

-- Set parent relationships (second pass after all rows exist)
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '406.000') WHERE account_code IN ('406.111','406.112','406.115','406.118','406.119');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '405.000') WHERE account_code IN ('405.106','405.112','405.113','405.119');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '407.000') WHERE account_code IN ('407.602','407.603','407.700','407.727');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '501.000') WHERE account_code IN ('501.151','501.153','501.154','501.155','501.156','501.157','501.158');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '502.000') WHERE account_code IN ('502.161','502.164','502.169','502.174','502.182');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '502.500') WHERE account_code IN ('502.175','502.176','502.177');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '504.000') WHERE account_code IN ('504.101','504.102','504.106','504.112','504.113','504.115');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '505.000') WHERE account_code IN ('505.106','505.111','505.113');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '506.000') WHERE account_code IN ('506.201','506.203','506.318','506.319');
UPDATE chart_of_accounts SET parent_id = (SELECT id FROM chart_of_accounts WHERE account_code = '507.000') WHERE account_code IN ('507.602','507.603','507.615','507.700','507.725','507.727');

-- ── Bank Accounts ──
INSERT INTO bank_accounts (account_number_last4, account_name, coa_account_id) VALUES
  ('6193', 'Reserved Funds Checking', (SELECT id FROM chart_of_accounts WHERE account_code = '100.100')),
  ('5633', 'General Fund Checking',   (SELECT id FROM chart_of_accounts WHERE account_code = '100.000'))
ON CONFLICT DO NOTHING;

-- ── Statement Periods — June 2026 ──
INSERT INTO statement_periods
  (bank_account_id, period_start, period_end, beginning_balance, ending_balance, total_credits, total_debits, interest_earned)
VALUES
  ((SELECT id FROM bank_accounts WHERE account_number_last4 = '6193'),
   '2026-05-30', '2026-06-30', 77159.28, 75963.64, 153.53, 1349.17, 33.53),
  ((SELECT id FROM bank_accounts WHERE account_number_last4 = '5633'),
   '2026-05-30', '2026-06-30', 15304.72, 10340.96, 13143.70, 18107.46, 5.78)
ON CONFLICT DO NOTHING;

-- ── Transactions — Account 6193 ──
WITH sp AS (SELECT id FROM statement_periods sp JOIN bank_accounts ba ON ba.id = sp.bank_account_id WHERE ba.account_number_last4 = '6193' AND sp.period_end = '2026-06-30')
INSERT INTO transactions (statement_period_id, bank_account_id, transaction_date, description, raw_description, amount, direction, transaction_type) VALUES
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='6193'), '2026-06-30', 'Youth Tithing - Dawn Auto',              'Dawn Autod FOX VALLEY UNITY Youth Tithing',                 20.00, 'credit', 'electronic_credit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='6193'), '2026-06-05', 'Capital Improvement Transfer In',         'Capital Improvement',                                      100.00, 'credit', 'other_credit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='6193'), '2026-06-30', 'Interest',                                'INTEREST',                                                  33.53, 'credit', 'other_credit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='6193'), '2026-06-03', 'Reimbursement Expenses',                  'Reimbursem FOX VALLEY UNITY Reimbursement Expenses',       262.31, 'debit',  'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='6193'), '2026-06-12', 'Reimbursement Expenses',                  'Reimbursem FOX VALLEY UNITY Reimbursement Expenses',       786.86, 'debit',  'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='6193'), '2026-06-24', 'Check #1154 - Darryl Richter (Outreach)', '#1154 Darryl Richter - Outreach',                         300.00, 'debit',  'check');

UPDATE transactions SET check_number = '1154' WHERE bank_account_id = (SELECT id FROM bank_accounts WHERE account_number_last4='6193') AND transaction_date = '2026-06-24';

-- ── Transactions — Account 5633 ──
WITH sp AS (SELECT id FROM statement_periods sp JOIN bank_accounts ba ON ba.id = sp.bank_account_id WHERE ba.account_number_last4 = '5633' AND sp.period_end = '2026-06-30')
INSERT INTO transactions (statement_period_id, bank_account_id, transaction_date, description, raw_description, amount, direction, transaction_type) VALUES
  -- DEPOSITS
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-01', 'Sunday Offering Deposit',         'DEPOSIT', 1563.00, 'credit', 'deposit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-08', 'Sunday Offering Deposit',         'DEPOSIT', 2559.00, 'credit', 'deposit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-15', 'Sunday Offering Deposit',         'DEPOSIT',  132.00, 'credit', 'deposit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-22', 'Sunday Offering Deposit',         'DEPOSIT', 1991.00, 'credit', 'deposit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-26', 'Sunday Offering Deposit',         'DEPOSIT', 2730.00, 'credit', 'deposit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-29', 'Sunday Offering Deposit',         'DEPOSIT', 1233.00, 'credit', 'deposit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-30', 'Sunday Offering Deposit',         'DEPOSIT', 1052.00, 'credit', 'deposit'),
  -- ELECTRONIC CREDITS
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-03', 'Tithing - Bonnie Bur',            'Bonnie Bur FOX VALLEY UNITY Tithing',   100.00, 'credit', 'electronic_credit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-16', 'Monthly Tithe',                   'Tithing FOX VALLEY UNITY Monthly Tithe', 1460.00, 'credit', 'electronic_credit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-18', 'Young Living Commission',         'Young Living COMMISSION 702017',          317.92, 'credit', 'electronic_credit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-30', 'Interest',                        'INTEREST',                                  5.78, 'credit', 'other_credit'),
  -- ELECTRONIC DEBITS
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-02', 'Google Workspace',                'Google Workspace Mountain View CA',        33.60, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-03', 'Microsoft 365',                   'Microsoft Corpo Tumwater WA',               9.72, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-03', 'FedEx Office - Printing',         'FEDEX OFFICE 008 PLANO TX',               84.22, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-03', 'Young Living Order',              'YOUNG LIVING 8003713515 UT',             166.23, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-05', 'Capital Improvement Transfer Out','Capital Improvement',                     100.00, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-05', 'FedEx Office - Printing',         'FEDEX OFFICE 008 PLANO TX',               90.47, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-08', 'Amazon Purchase',                 'AMAZON.COM O32BH SEATTLE WA',            139.99, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-09', 'FedEx Office - Printing',         'FEDEX OFFICE 008 PLANO TX',              158.06, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-10', 'FedEx Office - Printing',         'FEDEX OFFICE 148 BATAVIA IL',             21.58, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-10', 'WWP Pro Care Law - Batavia',       'WWP PRO CARE LAW BATAVIA IL',            136.56, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-16', 'GuideOne Insurance',              'GuideOne Insuran West Des Moin IA',       971.53, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-22', 'Robly Email Marketing',           'ROBLY DIGITAL MK JERSEY CITY NJ',          10.50, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-22', 'Amazon Purchase',                 'AMAZON.COM M50FB SEATTLE WA',             27.68, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-23', 'City of Batavia Utilities',       'CITYOFBATAVIAUTI BATAVIA IL',            289.46, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-23', 'Comcast / Xfinity',               'COMCAST / XFINIT SCHAUMBURG IL',         341.70, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-29', 'Unity Worldwide Ministries',      'UNITY WORLDWIDE UNITY VILLAGE MO',       250.00, 'debit', 'electronic_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-30', 'FedEx Office - Printing',         'FEDEX OFFICE 008 PLANO TX',               31.20, 'debit', 'electronic_debit'),
  -- OTHER DEBITS
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-03', 'Dawn Reimbursement',              'FOX VALLEY UNITY Dawn Reimb XXXXX1532',    50.00, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-03', 'Mortgage Payment',                'Mortgage - FOX VALLEY UNITY',            890.00, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-04', 'Nicor Gas',                       'Nicor Gas GAS PAYMNT 3418221000',        227.26, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-05', 'AJ Reimb - OfficeMax (50th Anniv)','AJ - Reimb FOX VALLEY UNITY Reimbursement for Office Max - Golden Anniversary', 56.35, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-05', 'AJ Reimb - OfficeMax (50th Anniv)','AJ - Reimb FOX VALLEY UNITY Reimbursement for Office Max - Golden Anniversary', 175.14, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-10', 'Paychex EIB Invoice',             'PAYCHEX EIB INVOICE X17053800047540',     55.80, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-12', 'Paychex Payroll Taxes',           'PAYCHEX TPS TAXES 17222700012495X',      444.35, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-12', 'Manse Payment',                   'FOX VALLEY UNITY Manse Reoc XXXXX1532', 1375.00, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-12', 'Paychex Payroll',                 'PAYCHEX INC. PAYROLL IOpAfAJXxk00FFI', 3370.74, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-18', 'Mimi Cleaning',                   'FOX VALLEY UNITY MIMI CLEAN XXXXX1532',  720.00, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-22', 'Alarm Detection',                 'ALARM DETECTION WEB COLL 27015',         373.95, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-23', 'TTSG Inc - Total Tech',           'TTSG, INC TOTAL TECH ID6IQF6J2T',         69.95, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-26', 'Paychex Payroll Taxes',           'PAYCHEX TPS TAXES 17416100007100X',      454.48, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-26', 'Manse Payment',                   'FOX VALLEY UNITY Manse Reoc XXXXX1532', 1375.00, 'debit', 'other_debit'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-26', 'Paychex Payroll',                 'PAYCHEX INC. PAYROLL RN3n9heKuOgM3LL', 3414.44, 'debit', 'other_debit'),
  -- CHECKS
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-18', 'Check #16666 - Kim Earn-Stryker',  '#16666 Kim Earn-Stryker',               100.00, 'debit', 'check'),
  ((SELECT id FROM sp), (SELECT id FROM bank_accounts WHERE account_number_last4='5633'), '2026-06-23', 'Check #16668 - S&S Catering (BBQ Event)', '#16668 S&s Catering - Barbeque event at Unity of Fox Valley', 2092.50, 'debit', 'check');

UPDATE transactions SET check_number = '16666' WHERE bank_account_id = (SELECT id FROM bank_accounts WHERE account_number_last4='5633') AND transaction_date = '2026-06-18' AND amount = 100.00;
UPDATE transactions SET check_number = '16668' WHERE bank_account_id = (SELECT id FROM bank_accounts WHERE account_number_last4='5633') AND transaction_date = '2026-06-23' AND amount = 2092.50;
