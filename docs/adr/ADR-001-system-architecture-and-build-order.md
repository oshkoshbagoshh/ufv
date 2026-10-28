# ADR-001: UFV System Architecture and Phased Build Order

**Status:** Accepted  
**Date:** 2026-07-11  
**Deciders:** AJ (technical lead)

---

## Context

Unity of Fox Valley (UFV) needs a unified backend system to handle financial ETL (bank statement reconciliation, bookkeeping), internal operations, communications, and eventually a member-facing portal. The codebase (`src/etl/logia.py`) already has a working file-extraction and inventory layer. A bank reconciliation schema has been created (`schema.sql`). FastAPI is installed and partially scaffolded.

**Current problem:** The Git working tree contains staged changes that include sensitive church records (PDFs, tax documents, audio files, spreadsheets, macOS metadata, email files, and ZIP archives under `data/downloads/`). Committing these would permanently embed private member and financial data into version history. The repository must be secured before any further feature work.

**Constraint:** The `data/` directory is the ETL landing zone for processed files. It must never be committed. The `Downloads.zip` at the project root is already `.gitignore`-d but the unpacked `data/downloads/` contents may not be fully excluded from staged changes.

---

## Decision

**Clean and secure the repository first. Do not build new FastAPI endpoints until the repo is safe.**

Execution order is non-negotiable:

1. Repo cleanup and `.gitignore` hardening  
2. Sensitive data migration to protected storage  
3. Database initialization  
4. FastAPI backend (bookkeeping / ETL endpoints)  
5. Configuration and secrets management  
6. Communications module  
7. Ops Control Center  
8. React frontend  
9. Networking and device management  
10. HR module  
11. Deployment

---

## Phase 0 — Repository Cleanup (DO THIS NOW)

### 0.1 Unstage everything

```bash
git reset HEAD
```

### 0.2 Verify `.gitignore` covers all sensitive paths

The current `.gitignore` has `downloads/` (no leading slash), which matches `data/downloads/` anywhere in the tree. Confirm it also covers:

```gitignore
# ── Data / ETL working directory ──────────────────────────────
data/
!data/.gitkeep

# ── Sensitive document types ──────────────────────────────────
*.pdf
*.docx
*.xlsx
*.xls
*.csv
*.mp3
*.mp4
*.wav
*.m4a
*.eml
*.msg
*.zip
*.7z
*.rar

# ── macOS metadata ────────────────────────────────────────────
__MACOSX/
.DS_Store
*.AppleDouble

# ── Compiled notebooks ────────────────────────────────────────
.ipynb_checkpoints/

# ── Schema files with real data (keep sanitized versions only) ─
# Committed: schema.sql (DDL + seed with COA structure, no PII)
# Never commit: any SQL dump with real transaction data
*.dump
*.sql.gz
```

Add a `data/.gitkeep` so the directory structure is tracked without content:

```bash
echo "" > data/.gitkeep
git add data/.gitkeep
```

### 0.3 Move sensitive files out of the repo

Move `data/downloads/` to protected storage **outside** the repository:

```
~/Library/CloudStorage/GoogleDrive-amirjavadi25@gmail.com/Shared drives/ufv/church-records/downloads/
```

Or a local protected path:

```
~/Documents/UFV/protected/downloads/
```

Then delete from the working tree:

```bash
rm -rf data/downloads/
```

### 0.4 Confirm nothing sensitive is staged

```bash
git status
git diff --cached --name-only
```

If any sensitive file appears, remove it:

```bash
git rm --cached path/to/file
```

### 0.5 Commit the clean baseline

```bash
git add .gitignore schema.sql docs/ CLAUDE.md
git commit -m "chore: harden .gitignore, add schema and ADR, remove sensitive data from tracking"
```

---

## Phase 1 — Database Initialization

`schema.sql` (at project root) contains the full DDL + seed for:
- `chart_of_accounts` — full COA hierarchy from QuickBooks export
- `bank_accounts` — accounts ...6193 (Reserved Funds) and ...5633 (General Fund)
- `statement_periods` — June 2026 periods with opening/closing balances
- `transactions` — all 51 transactions from both June statements
- `transaction_codings` — split-coding support with auto-`is_coded` trigger
- Views: `v_uncoded_transactions`, `v_period_summary`

**Initialize:**

```bash
# PostgreSQL (recommended for production)
createdb ufv
psql ufv < schema.sql

# Or SQLite for local dev
# (Requires adapting schema: remove SERIAL → INTEGER PRIMARY KEY AUTOINCREMENT,
#  remove triggers, adjust TIMESTAMPTZ → TEXT)
```

Add database config to `.env` (never commit):

```env
DATABASE_URL=postgresql://localhost/ufv
```

---

## Phase 2 — FastAPI Backend

### Current state

`src/api/main.py` has three endpoints:
- `GET /extract-downloads` — calls `Logia.extract_downloads()`
- `GET /analyze` — stub
- `GET /publish` — stub

`src/etl/logia.py` has working `extract()`, `extract_downloads()`, and `analyze_downloads()` methods. The analyze and publish methods are stubs awaiting the database layer.

### Next endpoints to build (in order)

| Endpoint | Method | Description |
|---|---|---|
| `/transactions` | GET | List transactions, filterable by account / period / coded status |
| `/transactions/{id}/code` | POST | Assign COA accounts to a transaction (split support) |
| `/accounts` | GET | List chart of accounts |
| `/periods/{id}/summary` | GET | Reconciliation summary for a statement period |
| `/periods/{id}/reconcile` | POST | Mark period as reconciled |
| `/analyze` | GET | Replace stub: run full reconciliation analysis |
| `/publish` | POST | Replace stub: export coded transactions to QuickBooks-compatible format |

### Architecture

```
src/
  api/
    main.py          # FastAPI app + router registration
    routers/
      transactions.py
      accounts.py
      periods.py
    deps.py          # DB session dependency
  etl/
    logia.py         # Core ETL class
    files.py         # File utilities (existing)
  db/
    models.py        # SQLAlchemy ORM models (mirrors schema.sql)
    session.py       # Engine + SessionLocal
    crud/
      transactions.py
      codings.py
      periods.py
```

**ORM:** SQLAlchemy 2.x with async session  
**Migrations:** Alembic (add after initial schema stabilizes)  
**Config:** Pydantic `BaseSettings` reading from `.env`

---

## Phase 3 — Configuration & Secrets

```bash
uv add pydantic-settings python-dotenv
```

`src/config.py`:
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    environment: str = "development"
    
    class Config:
        env_file = ".env"
```

`.env.example` (commit this, never `.env`):
```env
DATABASE_URL=postgresql://localhost/ufv
ENVIRONMENT=development
```

---

## Phase 4 — Communications Module

Handles outbound email/SMS for member communications, giving reports, and reminders.

- Integrate with existing Robly Digital MK subscription (seen in bank statement: $10.50/mo)  
- Or replace with self-hosted option (Mailgun, Resend) for cost control  
- Endpoints: `/communications/draft`, `/communications/send`, `/communications/templates`

---

## Phase 5 — Ops Control Center

Internal dashboard for bookkeeping, reconciliation, and reporting.

- Bank statement import (upload PDF → parse → insert transactions)  
- Transaction coding UI (maps to `transaction_codings` table)  
- Period reconciliation workflow  
- COA management  
- Reports: P&L by fund, budget vs. actual, special fund balances

---

## Phase 6 — React Frontend

Thin React + Vite SPA consuming the FastAPI backend.

```
frontend/
  src/
    pages/
      Reconciliation.tsx
      Transactions.tsx
      Reports.tsx
    components/
    api/          # typed fetch wrappers
```

**Auth:** JWT issued by FastAPI, stored in httpOnly cookie

---

## Phase 7 — Networking & Device Management

Internal network configuration, Wi-Fi, and device inventory for the Batavia campus.

---

## Phase 8 — HR Module

Staff and volunteer management. Integrates with Paychex (already in bank statement as recurring ACH) for payroll data import.

- Employee records linked to COA compensation accounts (504.xxx)
- Paystub import from Paychex portal
- Volunteer hours tracking

---

## Phase 9 — Deployment

| Concern | Choice |
|---|---|
| Hosting | Self-hosted on church hardware or low-cost VPS (e.g., Hetzner) |
| Process manager | `systemd` or Docker Compose |
| Reverse proxy | Nginx |
| TLS | Let's Encrypt via Certbot |
| DB backups | `pg_dump` to Google Drive (already connected) |
| Secrets | `.env` file, file permissions 600, never in Git |

```bash
# Run API
uv run uvicorn src.api.main:app --host 0.0.0.0 --port 8000
```

---

## Options Considered

| Dimension | Option A: Monolith (chosen) | Option B: Microservices |
|---|---|---|
| Complexity | Low | High |
| Deployment | Single process | Multiple containers |
| Team size fit | 1–3 people | 5+ people |
| Cost | Minimal | Higher infra overhead |
| Phase match | Natural for church scale | Overkill |

---

## Consequences

**What becomes easier:**
- All church financial data stays in one PostgreSQL database, queryable directly
- `Logia` class grows organically without duplicating logic between notebook and API
- Clean Git history with no embedded PII

**What becomes harder:**
- Schema migrations require Alembic discipline once data is live
- Sensitive document storage outside the repo needs a clear access protocol for the team

**What we'll need to revisit:**
- Whether to keep the Jupyter notebook workflow long-term or fully migrate to the API
- Paychex API integration vs. manual import
- Multi-user auth if other staff need access to the Ops Control Center

---

## Action Items

- [ ] **Phase 0.1** — `git reset HEAD` — unstage everything
- [ ] **Phase 0.2** — Patch `.gitignore` with additions above
- [ ] **Phase 0.3** — Move `data/downloads/` to Google Drive protected folder
- [ ] **Phase 0.4** — Verify `git status` is clean, commit baseline
- [ ] **Phase 1** — `psql ufv < schema.sql` — initialize database
- [ ] **Phase 1** — Add `DATABASE_URL` to `.env`
- [ ] **Phase 2** — Add SQLAlchemy models mirroring `schema.sql`
- [ ] **Phase 2** — Build `/transactions` and `/transactions/{id}/code` endpoints
- [ ] **Phase 2** — Replace `analyze()` and `publish()` stubs with real DB queries
- [ ] **Phase 3** — Add `pydantic-settings`, wire `.env` to FastAPI config
- [ ] **Ongoing** — Code transactions from June 2026 statements into `transaction_codings`
