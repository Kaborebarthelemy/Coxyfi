-- =============================================================================
-- seed_perf_test.sql – CoxyFi – Performance dataset (100,000 rows)
-- Usage: mysql -u<user> -p <db> < scripts/seed_perf_test.sql
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
SET autocommit = 0;

-- Procedure for generating synthetic data
DROP PROCEDURE IF EXISTS coxyfi_seed_perf;

DELIMITER $$

CREATE PROCEDURE coxyfi_seed_perf()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE asset_sym VARCHAR(32);
    DECLARE offer_status ENUM('open','matched','cancelled','expired','liquidated');
    DECLARE loan_status  ENUM('active','repaid','defaulted','liquidated','cancelled');
    DECLARE offer_type   ENUM('lend','borrow');
    DECLARE wallet_lender  VARCHAR(66);
    DECLARE wallet_borrower VARCHAR(66);
    DECLARE asset_addr    VARCHAR(66);
    DECLARE collat_addr   VARCHAR(66);
    DECLARE on_chain_offer VARCHAR(128);
    DECLARE on_chain_loan  VARCHAR(128);
    DECLARE blk_ts         DATETIME(3);
    DECLARE dur_sec        INT UNSIGNED;
    DECLARE principal      DECIMAL(36,18);
    DECLARE rate_bps       INT UNSIGNED;
    DECLARE offer_id_local BIGINT UNSIGNED;

    -- -----------------------------------------------------------------------
    -- Minimal registry entries for the assets used in the offers
    -- -----------------------------------------------------------------------
    INSERT IGNORE INTO registry (entity_type, chain_id, address, name, symbol, decimals, is_verified, is_active)
    VALUES
      ('asset', 1, '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', 'USD Coin',        'USDC', 6,  1, 1),
      ('asset', 1, '0xdAC17F958D2ee523a2206206994597C13D831ec7', 'Tether USD',       'USDT', 6,  1, 1),
      ('asset', 1, '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', 'Wrapped BTC',      'WBTC', 8,  1, 1),
      ('asset', 1, '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', 'Wrapped Ether',    'WETH', 18, 1, 1),
      ('asset', 1, '0x6B175474E89094C44Da98b954EedeAC495271d0F', 'Dai Stablecoin',   'DAI',  18, 1, 1);

    -- -----------------------------------------------------------------------
    -- Main loop: 100,000 offers and ~50,000 loans
    -- -----------------------------------------------------------------------
    WHILE i <= 100000 DO

        -- Pseudo-random deterministic generation
        SET asset_sym       = ELT(1 + (i MOD 5), 'USDC','USDT','WBTC','WETH','DAI');
        SET asset_addr      = ELT(1 + (i MOD 5),
            '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
            '0xdAC17F958D2ee523a2206206994597C13D831ec7',
            '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
            '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
            '0x6B175474E89094C44Da98b954EedeAC495271d0F');
        SET collat_addr     = ELT(1 + ((i+2) MOD 5),
            '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
            '0xdAC17F958D2ee523a2206206994597C13D831ec7',
            '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
            '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
            '0x6B175474E89094C44Da98b954EedeAC495271d0F');
        SET offer_status    = ELT(1 + (i MOD 5), 'open','matched','cancelled','expired','liquidated');
        SET offer_type      = ELT(1 + (i MOD 2), 'lend','borrow');
        SET wallet_lender   = CONCAT('0x', LPAD(HEX(i * 7 + 1000000), 40, '0'));
        SET wallet_borrower = CONCAT('0x', LPAD(HEX(i * 13 + 2000000), 40, '0'));
        SET on_chain_offer  = CONCAT('0x', LPAD(HEX(i), 64, '0'));
        SET blk_ts          = DATE_SUB(NOW(3), INTERVAL (100001 - i) MINUTE);
        SET dur_sec         = (1 + (i MOD 30)) * 86400; -- 1 à 30 jours
        SET principal       = (100 + (i MOD 9901)) + 0.000000000000000001;
        SET rate_bps        = 50 + (i MOD 950);  -- 0.5% à 10%

        INSERT INTO offers (
            on_chain_id, offer_type, status,
            lender_address, borrower_address,
            asset_address, asset_symbol,
            principal_amount, interest_rate_bps, duration_seconds,
            collateral_address, collateral_symbol, collateral_amount, ltv_bps,
            chain_id, block_number, block_timestamp, tx_hash, log_index,
            expires_at
        ) VALUES (
            on_chain_offer, offer_type, offer_status,
            wallet_lender,
            IF(offer_status IN ('matched','liquidated'), wallet_borrower, NULL),
            asset_addr, asset_sym,
            principal, rate_bps, dur_sec,
            collat_addr, ELT(1 + ((i+2) MOD 5), 'USDC','USDT','WBTC','WETH','DAI'),
            principal * 1.5, 6667,
            1, 17000000 + i, blk_ts,
            CONCAT('0x', LPAD(HEX(i * 31), 64, '0')), i MOD 100,
            DATE_ADD(blk_ts, INTERVAL dur_sec SECOND)
        );

        -- Creation of a loan for ~50% of matched offers
        IF offer_status = 'matched' AND (i MOD 2 = 0) THEN
            SET offer_id_local = LAST_INSERT_ID();
            SET on_chain_loan  = CONCAT('0xL', LPAD(HEX(i), 63, '0'));
            SET loan_status    = ELT(1 + (i MOD 3), 'active','repaid','defaulted');

            INSERT INTO loans (
                on_chain_id, offer_id, status,
                lender_address, borrower_address,
                asset_address, asset_symbol,
                principal_amount, interest_rate_bps, duration_seconds,
                collateral_address, collateral_symbol, collateral_amount, ltv_bps,
                amount_repaid, interest_accrued,
                chain_id, originated_block, originated_at, originated_tx,
                due_at,
                closed_at, closed_tx
            ) VALUES (
                on_chain_loan, offer_id_local, loan_status,
                wallet_lender, wallet_borrower,
                asset_addr, asset_sym,
                principal, rate_bps, dur_sec,
                collat_addr, ELT(1 + ((i+2) MOD 5), 'USDC','USDT','WBTC','WETH','DAI'),
                principal * 1.5, 6667,
                IF(loan_status != 'active', principal + (principal * rate_bps / 10000), 0),
                principal * rate_bps / 10000 * dur_sec / 31536000,
                1, 17000000 + i + 1,
                DATE_ADD(blk_ts, INTERVAL 5 MINUTE),
                CONCAT('0x', LPAD(HEX(i * 37), 64, '0')),
                DATE_ADD(blk_ts, INTERVAL dur_sec + 300 SECOND),
                IF(loan_status != 'active', DATE_ADD(blk_ts, INTERVAL (dur_sec * 0.9) SECOND), NULL),
                IF(loan_status != 'active', CONCAT('0x', LPAD(HEX(i * 41), 64, '0')), NULL)
            );
        END IF;

        -- Committed in batches of 1,000 for performance
        IF (i MOD 1000 = 0) THEN
            COMMIT;
        END IF;

        SET i = i + 1;
    END WHILE;

    COMMIT;

    -- users_alias pour les wallets générés
    INSERT IGNORE INTO users_alias (wallet_address, alias, alias_type, is_primary)
    SELECT lender_address, CONCAT('user_', SUBSTRING(lender_address, 3, 8)), 'username', 1
    FROM   offers
    LIMIT  1000;

END$$

DELIMITER ;

CALL coxyfi_seed_perf();
DROP PROCEDURE IF EXISTS coxyfi_seed_perf;

SET FOREIGN_KEY_CHECKS = 1;
SET autocommit = 1;

SELECT 'Seed terminé.' AS status;
SELECT COUNT(*) AS nb_offers FROM offers;
SELECT COUNT(*) AS nb_loans  FROM loans;
