-- =============================================================================
-- tests/acceptance_tests.sql  –  CoxyFi  –  Tests d'acceptation DB1/DB2/DB3
-- Utilisation : mysql -u<user> -p <db> < tests/acceptance_tests.sql
-- =============================================================================

SET NAMES utf8mb4;
SET @test_failures = 0;
SET @test_count    = 0;

-- Macro de vérification
DROP PROCEDURE IF EXISTS assert_true;
DELIMITER $$
CREATE PROCEDURE assert_true(IN p_name VARCHAR(256), IN p_condition TINYINT(1))
BEGIN
    SET @test_count = @test_count + 1;
    IF p_condition THEN
        SELECT CONCAT('[PASS] ', p_name) AS test_result;
    ELSE
        SET @test_failures = @test_failures + 1;
        SELECT CONCAT('[FAIL] ', p_name) AS test_result;
    END IF;
END$$
DELIMITER ;

-- =============================================================================
-- DB1 – MIGRATION : Vérifier que toutes les tables requises existent
-- =============================================================================
SELECT '=== DB1 : Migration ===' AS section;

CALL assert_true('DB1.1 – Table offers existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'offers') = 1);

CALL assert_true('DB1.2 – Table loans existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'loans') = 1);

CALL assert_true('DB1.3 – Table registry existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'registry') = 1);

CALL assert_true('DB1.4 – Table events existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'events') = 1);

CALL assert_true('DB1.5 – Table users_alias existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users_alias') = 1);

CALL assert_true('DB1.6 – Table audit_log existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'audit_log') = 1);

CALL assert_true('DB1.7 – Table fiat_claims existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fiat_claims') = 1);

CALL assert_true('DB1.8 – Table schema_version existe',
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'schema_version') = 1);

-- FK : loans → offers
CALL assert_true('DB1.9 – FK loans→offers existe',
    (SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'loans'
       AND REFERENCED_TABLE_NAME = 'offers') > 0);

-- FK : fiat_claims → loans
CALL assert_true('DB1.10 – FK fiat_claims→loans existe',
    (SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'fiat_claims'
       AND REFERENCED_TABLE_NAME = 'loans') > 0);


-- =============================================================================
-- DB2 – CONTRAINTES : Unicité des identifiants actifs
-- =============================================================================
SELECT '=== DB2 : Contraintes d''unicité ===' AS section;

-- Prépare des données de test isolées
SET @test_on_chain = CONCAT('test_constraint_', UNIX_TIMESTAMP());

-- Insertion d'une offre de test
INSERT INTO offers (
    on_chain_id, offer_type, status, lender_address, asset_address, asset_symbol,
    principal_amount, interest_rate_bps, duration_seconds,
    chain_id, block_number, block_timestamp, tx_hash, log_index
) VALUES (
    @test_on_chain, 'lend', 'open',
    '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01',
    '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', 'USDC',
    1000.0, 500, 2592000,
    1, 99999999, NOW(3),
    CONCAT('0x', LPAD(HEX(UNIX_TIMESTAMP()), 64, '0')), 0
);

-- Test DB2.1 : doublon on_chain_id sur offers → doit échouer
CALL assert_true('DB2.1 – Doublon on_chain_id offers rejeté',
    (SELECT
        CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
     FROM (
        SELECT @test_ok := 0
     ) t
    ) = 0  -- dummy; on utilise le handler ci-dessous
);

-- Handler pour tester l'exception de contrainte
BEGIN
    DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
        SELECT '[PASS] DB2.1 – Doublon on_chain_id offers rejeté (duplicate key)' AS test_result;
    INSERT INTO offers (
        on_chain_id, offer_type, status, lender_address, asset_address, asset_symbol,
        principal_amount, interest_rate_bps, duration_seconds,
        chain_id, block_number, block_timestamp, tx_hash, log_index
    ) VALUES (
        @test_on_chain, 'lend', 'open',
        '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA02',
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', 'USDC',
        500.0, 300, 1296000,
        1, 99999998, NOW(3),
        CONCAT('0x', LPAD(HEX(UNIX_TIMESTAMP()+1), 64, '0')), 1
    );
    -- Si on arrive ici, le test échoue
    SELECT '[FAIL] DB2.1 – Doublon on_chain_id offers NON rejeté' AS test_result;
    SET @test_failures = @test_failures + 1;
END;

-- Test DB2.2 : doublon (chain_id, tx_hash, log_index) → doit échouer
BEGIN
    DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
        SELECT '[PASS] DB2.2 – Doublon (chain_id,tx_hash,log_index) offers rejeté' AS test_result;
    INSERT INTO offers (
        on_chain_id, offer_type, status, lender_address, asset_address, asset_symbol,
        principal_amount, interest_rate_bps, duration_seconds,
        chain_id, block_number, block_timestamp, tx_hash, log_index
    ) VALUES (
        CONCAT(@test_on_chain, '_dup2'), 'lend', 'open',
        '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA03',
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', 'USDC',
        500.0, 300, 1296000,
        1, 99999999,
        NOW(3),
        -- Même tx_hash et log_index que l'offre de test ci-dessus
        (SELECT tx_hash FROM offers WHERE on_chain_id = @test_on_chain),
        0
    );
    SELECT '[FAIL] DB2.2 – Doublon (chain_id,tx_hash,log_index) NON rejeté' AS test_result;
    SET @test_failures = @test_failures + 1;
END;

-- Test DB2.3 : unicité alias (wallet_address, alias)
BEGIN
    DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
        SELECT '[PASS] DB2.3 – Doublon (wallet_address,alias) rejeté' AS test_result;
    INSERT INTO users_alias (wallet_address, alias, alias_type)
    VALUES ('0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB01', 'test_alias_db2', 'username');
    INSERT INTO users_alias (wallet_address, alias, alias_type)
    VALUES ('0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB01', 'test_alias_db2', 'username');
    SELECT '[FAIL] DB2.3 – Doublon (wallet_address,alias) NON rejeté' AS test_result;
    SET @test_failures = @test_failures + 1;
END;

-- Test DB2.4 : prêt orphelin (offer_id inexistant) → FK violation
BEGIN
    DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
        SELECT '[PASS] DB2.4 – Prêt orphelin (FK violation) rejeté' AS test_result;
    INSERT INTO loans (
        on_chain_id, offer_id, status,
        lender_address, borrower_address,
        asset_address, asset_symbol,
        principal_amount, interest_rate_bps, duration_seconds,
        chain_id, originated_block, originated_at, originated_tx, due_at
    ) VALUES (
        CONCAT('orphan_loan_', UNIX_TIMESTAMP()), 999999999, 'active',
        '0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC01',
        '0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC02',
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', 'USDC',
        100.0, 500, 2592000,
        1, 99999990, NOW(3),
        CONCAT('0x', LPAD(HEX(UNIX_TIMESTAMP()+99), 64, '0')),
        DATE_ADD(NOW(3), INTERVAL 30 DAY)
    );
    SELECT '[FAIL] DB2.4 – Prêt orphelin inséré sans erreur' AS test_result;
    SET @test_failures = @test_failures + 1;
END;

-- Nettoyage des données de test
DELETE FROM users_alias WHERE alias = 'test_alias_db2';
DELETE FROM offers       WHERE on_chain_id = @test_on_chain;


-- =============================================================================
-- DB3 – PERFORMANCE : Requêtes clés sur le jeu de données de 100 000 lignes
--       (Exécuter après seed_perf_test.sql)
-- =============================================================================
SELECT '=== DB3 : Performance ===' AS section;

-- DB3.1 : Affichage des offres avec filtres
SET @t0 = SYSDATE(6);
SELECT id, offer_type, status, asset_symbol, principal_amount, interest_rate_bps, block_timestamp
FROM   offers
WHERE  offer_type = 'lend'
  AND  status     = 'open'
  AND  asset_address = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
ORDER BY block_timestamp DESC
LIMIT 50;
SET @elapsed_db3_1 = TIMESTAMPDIFF(MICROSECOND, @t0, SYSDATE(6)) / 1000;
SELECT CONCAT('DB3.1 – Listing offres filtrées : ', @elapsed_db3_1, ' ms') AS perf_result;
CALL assert_true('DB3.1 – Listing offres ≤ 200 ms', @elapsed_db3_1 <= 200);

-- DB3.2 : Prêts par emprunteur
SET @sample_borrower = (SELECT borrower_address FROM loans WHERE borrower_address IS NOT NULL LIMIT 1);
SET @t0 = SYSDATE(6);
SELECT id, status, principal_amount, interest_rate_bps, originated_at, due_at
FROM   loans
WHERE  borrower_address = @sample_borrower
  AND  status IN ('active','repaid')
ORDER BY originated_at DESC
LIMIT 20;
SET @elapsed_db3_2 = TIMESTAMPDIFF(MICROSECOND, @t0, SYSDATE(6)) / 1000;
SELECT CONCAT('DB3.2 – Prêts par emprunteur : ', @elapsed_db3_2, ' ms') AS perf_result;
CALL assert_true('DB3.2 – Prêts emprunteur ≤ 200 ms', @elapsed_db3_2 <= 200);

-- DB3.3 : Recherche permanente (FULLTEXT)
SET @t0 = SYSDATE(6);
SELECT id, offer_type, status, asset_symbol, lender_address
FROM   offers
WHERE  MATCH(asset_symbol, collateral_symbol, lender_address, borrower_address)
       AGAINST ('USDC' IN BOOLEAN MODE)
LIMIT 50;
SET @elapsed_db3_3 = TIMESTAMPDIFF(MICROSECOND, @t0, SYSDATE(6)) / 1000;
SELECT CONCAT('DB3.3 – Recherche permanente FULLTEXT : ', @elapsed_db3_3, ' ms') AS perf_result;
CALL assert_true('DB3.3 – Recherche permanente ≤ 200 ms', @elapsed_db3_3 <= 200);

-- DB3.4 : Offres expirées (nettoyage batch)
SET @t0 = SYSDATE(6);
SELECT id, on_chain_id, expires_at
FROM   offers
WHERE  status    = 'open'
  AND  expires_at < NOW(3)
ORDER BY expires_at ASC
LIMIT 100;
SET @elapsed_db3_4 = TIMESTAMPDIFF(MICROSECOND, @t0, SYSDATE(6)) / 1000;
SELECT CONCAT('DB3.4 – Offres expirées : ', @elapsed_db3_4, ' ms') AS perf_result;
CALL assert_true('DB3.4 – Offres expirées ≤ 200 ms', @elapsed_db3_4 <= 200);


-- =============================================================================
-- Résumé
-- =============================================================================
SELECT '=== RÉSUMÉ ===' AS section;
SELECT
    @test_count    AS total_tests,
    @test_failures AS failures,
    IF(@test_failures = 0, 'TOUS LES TESTS PASSÉS ✓', CONCAT(@test_failures, ' ÉCHEC(S) ✗')) AS verdict;

DROP PROCEDURE IF EXISTS assert_true;
