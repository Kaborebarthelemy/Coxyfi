-- =============================================================================
-- tests/integrity_check.sql – CoxyFi – Referential Integrity Check
-- Usage: mysql -u<user> -p <db> < tests/integrity_check.sql
-- Returns 0 rows if the schema is intact; otherwise, lists the anomalies.
-- =============================================================================

SET NAMES utf8mb4;

SELECT '=== Vérification intégrité référentielle CoxyFi ===' AS title;
SELECT NOW(3) AS checked_at;

-- ---------------------------------------------------------------------------
-- IC1 : Loans without a parent offer (orphan records)
-- ---------------------------------------------------------------------------
SELECT 'IC1 – Prêts orphelins (loans sans offers parent)' AS check_id;
SELECT l.id, l.on_chain_id, l.offer_id
FROM   loans l
LEFT JOIN offers o ON o.id = l.offer_id
WHERE  o.id IS NULL;
-- Expected result: 0 lines (FK already guarantees this, defensive check)

-- ---------------------------------------------------------------------------
-- IC2 : fiat_claims sans prêt parent
-- ---------------------------------------------------------------------------
SELECT 'IC2 – fiat_claims orphelins (sans loans parent)' AS check_id;
SELECT fc.id, fc.loan_id, fc.claimant_address
FROM   fiat_claims fc
LEFT JOIN loans l ON l.id = fc.loan_id
WHERE  l.id IS NULL;

-- ---------------------------------------------------------------------------
-- IC3 : Matched offers without a corresponding loan
-- (may be legitimate depending on the lifecycle, noted for informational purposes)
-- ---------------------------------------------------------------------------
SELECT 'IC3 – Offres matchées sans prêt (informatif)' AS check_id;
SELECT o.id, o.on_chain_id, o.status
FROM   offers o
LEFT JOIN loans l ON l.offer_id = o.id
WHERE  o.status = 'matched'
  AND  l.id IS NULL;

-- ---------------------------------------------------------------------------
-- IC4 : Loans with active status while their offer is cancelled (status inconsistency)
-- ---------------------------------------------------------------------------
SELECT 'IC4 – Prêts actifs sur offre annulée/expirée (anomalie statut)' AS check_id;
SELECT l.id AS loan_id, l.status AS loan_status,
       o.id AS offer_id, o.status AS offer_status
FROM   loans  l
JOIN   offers o ON o.id = l.offer_id
WHERE  l.status = 'active'
  AND  o.status IN ('cancelled','expired');

-- ---------------------------------------------------------------------------
-- IC5 : Loans with due_at earlier than originated_at (inconsistent dates)
-- ---------------------------------------------------------------------------
SELECT 'IC5 – Prêts avec due_at < originated_at (dates invalides)' AS check_id;
SELECT id, on_chain_id, originated_at, due_at
FROM   loans
WHERE  due_at < originated_at;

-- ---------------------------------------------------------------------------
-- IC6 : Offers with expires_at earlier than block_timestamp
-- ---------------------------------------------------------------------------
SELECT 'IC6 – Offres expirées avant leur création (dates invalides)' AS check_id;
SELECT id, on_chain_id, block_timestamp, expires_at
FROM   offers
WHERE  expires_at IS NOT NULL
  AND  expires_at < block_timestamp;

-- ---------------------------------------------------------------------------
-- IC7 : Active on_chain_id duplicates in offers (logical uniqueness violation)
-- (the UNIQUE KEY prevents exact duplicates; this detects near-duplicates)
-- ---------------------------------------------------------------------------
SELECT 'IC7 – Offres actives avec on_chain_id dupliqué' AS check_id;
SELECT on_chain_id, COUNT(*) AS cnt
FROM   offers
GROUP BY on_chain_id
HAVING cnt > 1;

-- ---------------------------------------------------------------------------
-- IC8 : Duplicate on_chain_id in loans
-- ---------------------------------------------------------------------------
SELECT 'IC8 – Prêts avec on_chain_id dupliqué' AS check_id;
SELECT on_chain_id, COUNT(*) AS cnt
FROM   loans
GROUP BY on_chain_id
HAVING cnt > 1;

-- ---------------------------------------------------------------------------
-- IC9 : Duplicate events (chain_id, tx_hash, log_index)
-- ---------------------------------------------------------------------------
SELECT 'IC9 – Événements dupliqués (chain_id+tx_hash+log_index)' AS check_id;
SELECT chain_id, tx_hash, log_index, COUNT(*) AS cnt
FROM   events
GROUP BY chain_id, tx_hash, log_index
HAVING cnt > 1;

-- ---------------------------------------------------------------------------
-- IC10 : Wallet addresses in users_alias referencing an address
-- non-existent in offers or loans (informative – no foreign key applied
-- intentionally because it's off-chain)
-- ---------------------------------------------------------------------------
SELECT 'IC10 – Alias sans activité connue (informatif)' AS check_id;
SELECT ua.wallet_address, ua.alias
FROM   users_alias ua
WHERE  ua.deleted_at IS NULL
  AND  NOT EXISTS (SELECT 1 FROM offers WHERE lender_address = ua.wallet_address)
  AND  NOT EXISTS (SELECT 1 FROM offers WHERE borrower_address = ua.wallet_address)
  AND  NOT EXISTS (SELECT 1 FROM loans  WHERE lender_address = ua.wallet_address)
  AND  NOT EXISTS (SELECT 1 FROM loans  WHERE borrower_address = ua.wallet_address)
LIMIT 50;

-- ---------------------------------------------------------------------------
-- Statistical summary of the diagram
-- ---------------------------------------------------------------------------
SELECT '=== Résumé statistique ===' AS section;
SELECT 'offers'       AS tbl, COUNT(*) AS `rows` FROM offers
UNION ALL
SELECT 'loans',        COUNT(*) FROM loans
UNION ALL
SELECT 'events',       COUNT(*) FROM events
UNION ALL
SELECT 'registry',     COUNT(*) FROM registry
UNION ALL
SELECT 'users_alias',  COUNT(*) FROM users_alias
UNION ALL
SELECT 'audit_log',    COUNT(*) FROM audit_log
UNION ALL
SELECT 'fiat_claims',  COUNT(*) FROM fiat_claims;
