# coxyfi-mysql-schema

Normalized MySQL schema and migration workflow for the **coxyfio** platform.  
This repository addresses **Job-Milestone 7** (DB1, DB2, DB3 criteria).

---

## Table of Contents

1. [Schema Architecture](#schema-architecture)
2. [Project Structure](#project-structure)
3. [Migrations](#migrations)
4. [Indexing Strategy](#indexing-strategy)
5. [Acceptance Tests](#acceptance-tests)
6. [Execution Plans for the Top 10 Queries](#execution-plans)
7. [Referential Integrity](#referential-integrity)
8. [Expected Performance](#expected-performance)

---

## Schema Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CoxyFi – Schema v3                   │
│                                                         │
│  users_alias          registry          audit_log       │
│  ─────────────        ────────────      ──────────────  │
│  id (PK)              id (PK)           id (PK)         │
│  wallet_address ──┐   chain_id          actor_address   │
│  alias            │   address (UQ)      action          │
│  alias_type       │   symbol            entity_type     │
│  is_primary       │   decimals          entity_id       │
│                   │                     before_state    │
│                   │   events            after_state     │
│  offers           │   ────────────                      │
│  ─────────────────┘   id (PK)           fiat_claims     │
│  id (PK)              chain_id          ──────────────  │
│  on_chain_id (UQ)     tx_hash (UQ)      id (PK)         │
│  offer_type           block_number      loan_id ─────┐  │
│  status               event_name        status       │  │
│  lender_address       raw_data          amount_usd   │  │
│  borrower_address     processed         expires_at   │  │
│  asset_address                                       │  │
│  principal_amount     schema_version                 │  │
│  interest_rate_bps    ──────────────                 │  │
│  ↓ FK                 version (PK)                   │  │
│  loans                script                         │  │
│  ─────────────────    installed_at                   │  │
│  id (PK)              success                        │  │
│  on_chain_id (UQ) ────────────────────────────────── ┘  │
│  offer_id (FK→offers)                                   │
│  status                                                 │
│  borrower_address                                       │
│  principal_amount                                       │
│  amount_repaid                                          │
│  due_at                                                 │
└─────────────────────────────────────────────────────────┘
```

### Tables and Responsibilities

| Table | Role | Data Type |
|---|---|---|
| **offers** | On-chain loan offers (cache) | Chain state |
| **loans** | Active or closed loans | Chain state |
| **registry** | Catalog of assets/protocols | On-chain registry / reference data |
| **events** | Raw log of on-chain events | Append-only |
| **users_alias** | Application aliases for wallets | Off-chain |
| **audit_log** | Immutable mutation tracking | Append-only |
| **fiat_claims** | Fiat reimbursement claims | Off-chain / optional |
| **schema_version** | Migration history | Metadata |

---

## Project Structure

```
coxyfi-mysql-schema/
├── migrations/
│   ├── V1__init.sql                          # Full initial schema
│   ├── V2__add_fulltext_and_perf_indexes.sql # FULLTEXT + performance indexes
│   └── V3__schema_version_tracking.sql       # Version tracking table
├── scripts/
│   ├── migrate.sh                            # Migration runner (bash)
│   └── seed_perf_test.sql                    # 100,000-row dataset (DB3)
├── tests/
│   ├── acceptance_tests.sql                  # DB1, DB2, DB3 tests
│   ├── query_execution_plans.sql             # EXPLAIN for the top 10 queries
│   └── integrity_check.sql                   # Referential integrity verification
└── README.md
```

---

## Migrations

### Application (DB1 – single command)

```bash
# Environment variables
export DB_HOST=127.0.0.1
export DB_PORT=3306
export DB_NAME=[db_name]
export DB_USER=[user_name]
export DB_PASS=[your_password]

# Migration to the latest version
bash scripts/migrate.sh
```

The same command is idempotent: migrations that have already been applied are ignored.

#### With Flyway (recommended for CI/CD)

```bash
flyway   -url="jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}"   -user="${DB_USER}" -password="${DB_PASS}"   -locations="filesystem:migrations"   migrate
```

#### Dry-run (verification without applying)

```bash
bash scripts/migrate.sh --dry-run
```

### Migration Order

| Version | File | Description |
|---|---|---|
| 1 | `V1__init.sql` | Full initial schema (7 tables + keys) |
| 2 | `V2__add_fulltext_and_perf_indexes.sql` | FULLTEXT index + covering indexes |
| 3 | `V3__schema_version_tracking.sql` | `schema_version` table |

---

## Indexing Strategy

### Guiding Principles

1. **Cover filter and sort columns** for the most frequent UI queries using composite indexes.
2. **Application-level uniqueness** guaranteed by `UNIQUE KEY` constraints on on-chain identifiers (`on_chain_id`, `(chain_id, tx_hash, log_index)`).
3. **FULLTEXT** for text search (avoids unindexed `LIKE '%…%'` operations).
4. **Partial soft-delete indexes** (`deleted_at`) to ignore logically deleted records.
5. **No redundant indexes**: FK columns already benefit from covering indexes.

### Indexes per Table

#### `offers`

| Index | Columns | Justification |
|---|---|---|
| `PRIMARY` | `id` | Single lookup |
| `uq_on_chain_id` | `on_chain_id` | On-chain canonical uniqueness; indexer idempotency |
| `uq_tx_log` | `(chain_id, tx_hash, log_index)` | Source event uniqueness; detects replays |
| `idx_listing` | `(status, offer_type, block_timestamp DESC)` | Main listing query (Q1) |
| `idx_offers_filter_perf` | `(offer_type, status, asset_address, interest_rate_bps, principal_amount)` | Listing with multiple filters (Q1 covering) |
| `idx_lender_status` | `(lender_address, status)` | Lender's offers |
| `idx_asset_status` | `(asset_address, status)` | Filtering by asset |
| `idx_expires_at` | `expires_at` | Batch cleanup for expired offers |
| `ft_offers_search` | `(asset_symbol, collateral_symbol, lender_address, borrower_address)` | Full-text search (Q4) |

#### `loans`

| Index | Columns | Justification |
|---|---|---|
| `PRIMARY` | `id` | Single lookup |
| `uq_on_chain_id` | `on_chain_id` | Canonical uniqueness |
| `uq_offer_loan` | `offer_id` | Constraint: max 1 offer → 1 active loan |
| `idx_borrower_perf` | `(borrower_address, status, originated_at, principal_amount)` | Loans by borrower (Q2, covering) |
| `idx_lender_status` | `(lender_address, status)` | Loans by lender (Q3) |
| `idx_due_at` | `due_at` | Due date alerts (Q7) |
| `fk_loans_offer` | `offer_id` | FK lookup (automatically created by InnoDB) |

#### `events`

| Index | Columns | Justification |
|---|---|---|
| `uq_tx_log` | `(chain_id, tx_hash, log_index)` | Uniqueness; prevents indexer replays |
| `idx_events_pending_perf` | `(processed, chain_id, block_number, log_index)` | Indexer polling (Q6) – range scan on `processed=0` |
| `idx_contract_event` | `(contract_addr, event_name)` | Filtering by event type |

#### `registry`

| Index | Columns | Justification |
|---|---|---|
| `uq_chain_address` | `(chain_id, address)` | Canonical uniqueness per chain |
| `ft_registry_search` | `(name, symbol)` | Entity search by name/symbol |

#### `users_alias`

| Index | Columns | Justification |
|---|---|---|
| `uq_wallet_alias` | `(wallet_address, alias)` | Uniqueness of one alias per wallet |
| `idx_wallet_address` | `wallet_address` | Wallet alias lookup (Q9) |

#### `audit_log`

| Index | Columns | Justification |
|---|---|---|
| `idx_entity` | `(entity_type, entity_id)` | Audit trail of an entity (Q8) |
| `idx_actor_address` | `actor_address` | Actor history |
| `idx_created_at` | `created_at` | Time window |

---

## Acceptance Tests

### DB1 – Migration

```bash
# Apply on a blank database and verify
bash scripts/migrate.sh
mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < tests/acceptance_tests.sql
```

Assertions DB1.1 → DB1.10 verify the existence of the 7 required tables and the presence of FK constraints.

### DB2 – Uniqueness Constraints

```bash
mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < tests/acceptance_tests.sql
```

Tests DB2.1 → DB2.4:
- **DB2.1**: Duplicate `on_chain_id` on `offers` → `SQLSTATE 23000`
- **DB2.2**: Duplicate `(chain_id, tx_hash, log_index)` → `SQLSTATE 23000`
- **DB2.3**: Duplicate `(wallet_address, alias)` → `SQLSTATE 23000`
- **DB2.4**: Loan with a non-existent `offer_id` → FK violation

### DB3 – Performance (100,000 rows)

```bash
# 1. Load the dataset
mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < scripts/seed_perf_test.sql

# 2. Run performance tests
mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < tests/acceptance_tests.sql
```

Threshold: **≤ 200 ms** for each of the 4 measured queries (DB3.1 → DB3.4).

---

## Execution Plans

```bash
mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < tests/query_execution_plans.sql
```

| # | Query | Used Index | Expected Perf. |
|---|---|---|---|
| Q1 | Filtered offers listing | `idx_offers_filter_perf` | < 10 ms |
| Q2 | Active loans by borrower | `idx_borrower_perf` | < 5 ms |
| Q3 | Loans by lender | `idx_lender_status` | < 5 ms |
| Q4 | FULLTEXT search | `ft_offers_search` | < 50 ms |
| Q5 | Offer details (JOIN) | `uq_on_chain_id` + `uq_offer_loan` | < 1 ms |
| Q6 | Pending events | `idx_events_pending_perf` | < 5 ms |
| Q7 | Loans expiring in < 24h | `idx_due_at` | < 10 ms |
| Q8 | Audit log by entity | `idx_entity` | < 5 ms |
| Q9 | Wallet alias | `idx_wallet_address` | < 1 ms |
| Q10 | Loan volume by asset | `idx_asset_status` | < 100 ms |

---

## Referential Integrity

```bash
mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < tests/integrity_check.sql
```

The `integrity_check.sql` script verifies:

| Check | Description |
|---|---|
| IC1 | Orphaned loans (`loans` without a parent `offers`) |
| IC2 | Orphaned `fiat_claims` |
| IC3 | `matched` offers without a loan (informational) |
| IC4 | `active` loans on a `cancelled`/`expired` offer |
| IC5 | `due_at` < `originated_at` |
| IC6 | `expires_at` < `block_timestamp` |
| IC7 | Duplicate `on_chain_id` in `offers` |
| IC8 | Duplicate `on_chain_id` in `loans` |
| IC9 | Duplicate events |
| IC10 | Aliases with no known activity (informational) |

**Expected result**: 0 rows for IC1, IC2, IC4 → IC9 on a healthy schema.

---

## CI/CD Integration

```yaml
# GitHub Actions Example
- name: Migrate database
  run: bash scripts/migrate.sh
  env:
    DB_HOST: 127.0.0.1
    DB_PORT: 3306
    DB_NAME: [db_name]
    DB_USER: [user_name]
    DB_PASS: [your_password]

- name: Run acceptance tests
  run: |
    mysql -uuser_name -p${{ your_password }} db_name       < tests/acceptance_tests.sql | grep -E '(PASS|FAIL|verdict)'
```
