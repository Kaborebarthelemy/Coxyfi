-- =============================================================================
-- tests/integrity_check.sql  –  CoxyFi  –  Vérification de l'intégrité référentielle
-- Utilisation : mysql -u<user> -p <db> < tests/integrity_check.sql
-- Retourne 0 ligne si le schéma est intègre ; sinon liste les anomalies.
-- =============================================================================

SET NAMES utf8mb4;

SELECT '=== Vérification intégrité référentielle CoxyFi ===' AS title;
SELECT NOW(3) AS checked_at;

-- ---------------------------------------------------------------------------
-- IC1 : Prêts sans offre parente (enregistrements orphelins)
-- ---------------------------------------------------------------------------
SELECT 'IC1 – Prêts orphelins (loans sans offers parent)' AS check_id;
SELECT l.id, l.on_chain_id, l.offer_id
FROM   loans l
LEFT JOIN offers o ON o.id = l.offer_id
WHERE  o.id IS NULL;
-- Résultat attendu : 0 ligne (FK garantit déjà cela, vérification défensive)

-- ---------------------------------------------------------------------------
-- IC2 : fiat_claims sans prêt parent
-- ---------------------------------------------------------------------------
SELECT 'IC2 – fiat_claims orphelins (sans loans parent)' AS check_id;
SELECT fc.id, fc.loan_id, fc.claimant_address
FROM   fiat_claims fc
LEFT JOIN loans l ON l.id = fc.loan_id
WHERE  l.id IS NULL;

-- ---------------------------------------------------------------------------
-- IC3 : Offres matchées sans prêt correspondant
--        (peut être légitime selon le cycle de vie, signalé à titre informatif)
-- ---------------------------------------------------------------------------
SELECT 'IC3 – Offres matchées sans prêt (informatif)' AS check_id;
SELECT o.id, o.on_chain_id, o.status
FROM   offers o
LEFT JOIN loans l ON l.offer_id = o.id
WHERE  o.status = 'matched'
  AND  l.id IS NULL;

-- ---------------------------------------------------------------------------
-- IC4 : Prêts actifs dont l'offre est annulée (incohérence de statut)
-- ---------------------------------------------------------------------------
SELECT 'IC4 – Prêts actifs sur offre annulée/expirée (anomalie statut)' AS check_id;
SELECT l.id AS loan_id, l.status AS loan_status,
       o.id AS offer_id, o.status AS offer_status
FROM   loans  l
JOIN   offers o ON o.id = l.offer_id
WHERE  l.status = 'active'
  AND  o.status IN ('cancelled','expired');

-- ---------------------------------------------------------------------------
-- IC5 : Prêts avec due_at antérieur à originated_at (dates incohérentes)
-- ---------------------------------------------------------------------------
SELECT 'IC5 – Prêts avec due_at < originated_at (dates invalides)' AS check_id;
SELECT id, on_chain_id, originated_at, due_at
FROM   loans
WHERE  due_at < originated_at;

-- ---------------------------------------------------------------------------
-- IC6 : Offres avec expires_at antérieur à block_timestamp
-- ---------------------------------------------------------------------------
SELECT 'IC6 – Offres expirées avant leur création (dates invalides)' AS check_id;
SELECT id, on_chain_id, block_timestamp, expires_at
FROM   offers
WHERE  expires_at IS NOT NULL
  AND  expires_at < block_timestamp;

-- ---------------------------------------------------------------------------
-- IC7 : Doublons on_chain_id actifs dans offers (violation unicité logique)
--        (le UNIQUE KEY empêche les doublons exacts ; ceci détecte les quasi-doublons)
-- ---------------------------------------------------------------------------
SELECT 'IC7 – Offres actives avec on_chain_id dupliqué' AS check_id;
SELECT on_chain_id, COUNT(*) AS cnt
FROM   offers
GROUP BY on_chain_id
HAVING cnt > 1;

-- ---------------------------------------------------------------------------
-- IC8 : Doublons on_chain_id dans loans
-- ---------------------------------------------------------------------------
SELECT 'IC8 – Prêts avec on_chain_id dupliqué' AS check_id;
SELECT on_chain_id, COUNT(*) AS cnt
FROM   loans
GROUP BY on_chain_id
HAVING cnt > 1;

-- ---------------------------------------------------------------------------
-- IC9 : Événements dupliqués (chain_id, tx_hash, log_index)
-- ---------------------------------------------------------------------------
SELECT 'IC9 – Événements dupliqués (chain_id+tx_hash+log_index)' AS check_id;
SELECT chain_id, tx_hash, log_index, COUNT(*) AS cnt
FROM   events
GROUP BY chain_id, tx_hash, log_index
HAVING cnt > 1;

-- ---------------------------------------------------------------------------
-- IC10 : Adresses wallet_address dans users_alias référençant une adresse
--         inexistante dans offers ou loans (informatif – pas de FK appliquée
--         intentionnellement car off-chain)
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
-- Résumé statistique du schéma
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
