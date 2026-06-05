-- =============================================================================
-- tests/query_execution_plans.sql  –  CoxyFi  –  Plans d'exécution Top-10
-- Utilisation : mysql -u<user> -p <db> < tests/query_execution_plans.sql
-- =============================================================================
-- Ce fichier documente les 10 requêtes les plus fréquentes avec leur plan
-- EXPLAIN et les caractéristiques de performance attendues.
-- =============================================================================

SET NAMES utf8mb4;

SELECT '================================================================' AS sep;
SELECT 'CoxyFi – Plans d''exécution des 10 requêtes les plus fréquentes' AS title;
SELECT '================================================================' AS sep;


-- ============================================================
-- Q1 : Listing des offres ouvertes avec filtre type + asset
-- Endpoint  : GET /v1/offers?type=lend&asset=USDC&status=open
-- Index     : idx_offers_filter_perf (offer_type, status, asset_address, ...)
-- Perf.     : < 10 ms sur 100 k lignes (range scan + covering index)
-- ============================================================
SELECT 'Q1 – Listing offres filtrées' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, offer_type, status, asset_symbol, principal_amount,
       interest_rate_bps, duration_seconds, lender_address, block_timestamp
FROM   offers
WHERE  offer_type    = 'lend'
  AND  status        = 'open'
  AND  asset_address = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
ORDER BY block_timestamp DESC
LIMIT 50;


-- ============================================================
-- Q2 : Prêts actifs d'un emprunteur donné
-- Endpoint  : GET /v1/loans?borrower=0x...&status=active
-- Index     : idx_borrower_perf (borrower_address, status, originated_at, ...)
-- Perf.     : < 5 ms (ref lookup sur borrower_address + status)
-- ============================================================
SELECT 'Q2 – Prêts actifs par emprunteur' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, status, principal_amount, interest_rate_bps, originated_at, due_at, amount_repaid
FROM   loans
WHERE  borrower_address = '0x000000000000000000000000000000000000002a'
  AND  status           = 'active'
ORDER BY originated_at DESC
LIMIT 20;


-- ============================================================
-- Q3 : Prêts d'un prêteur donné (toutes statuts)
-- Endpoint  : GET /v1/loans?lender=0x...
-- Index     : idx_lender_status (lender_address, status)
-- Perf.     : < 5 ms
-- ============================================================
SELECT 'Q3 – Prêts par prêteur' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, status, borrower_address, principal_amount, originated_at, due_at
FROM   loans
WHERE  lender_address = '0x000000000000000000000000000000000000002a'
ORDER BY originated_at DESC
LIMIT 20;


-- ============================================================
-- Q4 : Recherche permanente d'offres (FULLTEXT)
-- Endpoint  : GET /v1/search?q=USDC
-- Index     : ft_offers_search (FULLTEXT)
-- Perf.     : < 50 ms (MySQL InnoDB FULLTEXT inverted index)
-- ============================================================
SELECT 'Q4 – Recherche FULLTEXT offres' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, offer_type, status, asset_symbol, principal_amount, lender_address
FROM   offers
WHERE  MATCH(asset_symbol, collateral_symbol, lender_address, borrower_address)
       AGAINST ('USDC' IN BOOLEAN MODE)
LIMIT 50;


-- ============================================================
-- Q5 : Détail d'une offre par on_chain_id (lookup unitaire)
-- Endpoint  : GET /v1/offers/:on_chain_id
-- Index     : uq_on_chain_id (UNIQUE – const lookup)
-- Perf.     : < 1 ms
-- ============================================================
SELECT 'Q5 – Détail offre par on_chain_id' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT o.*, l.id AS loan_id, l.status AS loan_status
FROM   offers o
LEFT JOIN loans l ON l.offer_id = o.id
WHERE  o.on_chain_id = '0x0000000000000000000000000000000000000000000000000000000000000001';


-- ============================================================
-- Q6 : Événements non traités à indexer (polling indexeur)
-- Usage     : Batch interne – indexer service
-- Index     : idx_events_pending_perf (processed, chain_id, block_number, log_index)
-- Perf.     : < 5 ms (range scan sur processed=0)
-- ============================================================
SELECT 'Q6 – Événements en attente de traitement' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, chain_id, block_number, block_timestamp, tx_hash, log_index,
       contract_addr, event_name, raw_data
FROM   events
WHERE  processed  = 0
  AND  chain_id   = 1
ORDER BY block_number ASC, log_index ASC
LIMIT 500;


-- ============================================================
-- Q7 : Prêts arrivant à échéance dans les prochaines 24h (alertes)
-- Usage     : Cron job de notification
-- Index     : idx_due_at (due_at)
-- Perf.     : < 10 ms
-- ============================================================
SELECT 'Q7 – Prêts expirant sous 24h' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, borrower_address, lender_address, principal_amount, due_at
FROM   loans
WHERE  status  = 'active'
  AND  due_at  BETWEEN NOW(3) AND DATE_ADD(NOW(3), INTERVAL 24 HOUR)
ORDER BY due_at ASC;


-- ============================================================
-- Q8 : Audit trail d'une entité (ex. offre #42)
-- Endpoint  : GET /v1/admin/audit?entity=offers&id=42
-- Index     : idx_entity (entity_type, entity_id)
-- Perf.     : < 5 ms
-- ============================================================
SELECT 'Q8 – Journal audit par entité' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, actor_address, action, before_state, after_state, created_at
FROM   audit_log
WHERE  entity_type = 'offers'
  AND  entity_id   = 42
ORDER BY created_at DESC
LIMIT 50;


-- ============================================================
-- Q9 : Lookup alias d'un portefeuille
-- Endpoint  : GET /v1/users/:wallet/aliases
-- Index     : idx_wallet_address (wallet_address)
-- Perf.     : < 1 ms
-- ============================================================
SELECT 'Q9 – Alias d''un portefeuille' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT id, alias, alias_type, is_primary, created_at
FROM   users_alias
WHERE  wallet_address = '0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA01'
  AND  deleted_at IS NULL
ORDER BY is_primary DESC, created_at ASC;


-- ============================================================
-- Q10 : Dashboard : volume de prêts par asset (agrégat)
-- Endpoint  : GET /v1/stats/loans-by-asset
-- Index     : idx_asset_status (asset_address, status)
-- Perf.     : < 100 ms (group by sur index covering partiel)
-- ============================================================
SELECT 'Q10 – Volume prêts par asset' AS query_id;
EXPLAIN FORMAT=TRADITIONAL
SELECT asset_symbol,
       COUNT(*)                                AS nb_loans,
       SUM(principal_amount)                   AS total_principal,
       AVG(interest_rate_bps)                  AS avg_rate_bps,
       SUM(CASE WHEN status='active'  THEN 1 ELSE 0 END) AS active,
       SUM(CASE WHEN status='repaid'  THEN 1 ELSE 0 END) AS repaid,
       SUM(CASE WHEN status='defaulted' THEN 1 ELSE 0 END) AS defaulted
FROM   loans
WHERE  status IN ('active','repaid','defaulted')
GROUP BY asset_symbol
ORDER BY total_principal DESC;
