# Scripts

Local dev workstation scripts for managing LMS services, builds, and database setup.

## Prerequisites

- Node.js v18+
- npm
- PostgreSQL client (psql) — for DB scripts
- Docker or Podman — for code-execution-engine only
- macOS or Linux (bash 3.x+ compatible)

## Service Port Map

| Service | Port | Type |
|---------|------|------|
| docs-service | 4000 | Next.js |
| user-service | 4001 | Next.js |
| organization-service | 4002 | Next.js |
| course-service | 4003 | Next.js |
| assessment-service | 4004 | Next.js |
| analytics-service | 4005 | Next.js |
| storage-service | 4006 | Next.js |
| dashboard-service | 4007 | Next.js |
| public-service | 4008 | Next.js |
| login-service | 4009 | Next.js |
| logging-service | 4010 | Next.js |
| learning-paths-service | 4011 | Next.js |
| rubric-service | 4012 | Next.js |
| assignment-service | 4013 | Next.js |
| notification-service | 4014 | Next.js |
| code-editor-service | 4015 | Next.js |
| code-execution-engine | 8000 | Python (Flask/Uvicorn) |
| algoristics (frontend) | 8080 | Vite + React |

---

## run-services.sh

Start, stop, restart, and monitor all backend services in dev mode.
Injects `DATABASE_URL`, `JWT_SECRET`, and MinIO config into each service automatically.

### Usage

```bash
# Start all services
./run-services.sh start

# Stop all services
./run-services.sh stop

# Restart everything
./run-services.sh restart

# Check which services are running
./run-services.sh status

# Validate all services have package.json and dev scripts
./run-services.sh build
```

### What it does

- Starts each Next.js service via `npm run dev` with the correct env vars.
- Starts code-execution-engine via its `run.sh` script (if present).
- Tracks PIDs in `tmp/pids/` and logs output to `logs/services/<service>.log`.
- On stop, sends SIGTERM first, waits 3 seconds, then SIGKILL if the process is still alive.
- Status output shows each service's primary endpoint URL.

### Environment variables

These can be overridden before running the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `JWT_SECRET` | `dev_jwt_secret_change_me` | JWT signing secret |
| `MINIO_ENDPOINT` | `http://localhost:9000` | MinIO storage endpoint |
| `MINIO_ACCESS_KEY` | `admin` | MinIO access key |
| `MINIO_SECRET_KEY` | `admin12345` | MinIO secret key |

The `DATABASE_URL` is hardcoded in the script for the shared dev database.

---

## build-services.sh

Build one, many, or all services. Supports sequential and parallel builds with optional dependency installation and artifact cleanup.

### Usage

```bash
# Build everything (all backends + frontend + code-execution-engine)
./build-services.sh

# Build a single service
./build-services.sh user-service

# Build multiple specific services
./build-services.sh user-service login-service rubric-service

# Build all backend services only
./build-services.sh --backend

# Build frontend only
./build-services.sh --frontend

# Build code-execution-engine only
./build-services.sh --cee

# Install deps before building
./build-services.sh --install user-service

# Clean build artifacts (.next / dist) before building
./build-services.sh --clean --backend

# Parallel build — all backends at once
./build-services.sh --backend --parallel

# Full fresh build — install, clean, build everything in parallel
./build-services.sh --install --clean --parallel
```

### Flags

| Flag | Description |
|------|-------------|
| `--install` | Run `npm install` before building each service |
| `--clean` | Remove `.next` / `dist` directories before building |
| `--parallel` | Build all targets concurrently (faster, mixed log output) |
| `--backend` | Build all 16 Next.js backend services |
| `--frontend` | Build the algoristics frontend (Vite) |
| `--cee` | Build code-execution-engine (Docker/Podman) |
| `--help` | Show usage help |

Flags can be combined freely. When no flags or service names are given, it builds everything.

### Build logs

All build output is written to `logs/builds/<service>.build.log`.
On failure, the summary points you to the exact log file.

### Code-execution-engine

This service is Python-based and builds via Makefile.
The script auto-detects whether Podman or Docker is available and uses the right target.
If neither is installed, it warns and skips — no crash.

---

## Database Scripts

### setup_db_users.sh

Reads `DATABASE_URL` from a `.env` file and runs `setup_db_users.sql` against the database.

```bash
./setup_db_users.sh
```

### setup_db_users.sql

Creates the `lms_super_admin` database user with `CREATEDB` privileges and grants full access on the `public` schema.

### grant_permissions.sql

Grants all privileges on tables, sequences, and functions in the `public` schema to the main dev database user.

Run manually via psql:

```bash
psql "$DATABASE_URL" -f grant_permissions.sql
```

### transfer_ownership.sql

Transfers ownership of all database objects (tables, sequences, functions, views) to `lms_super_admin`.

Run manually via psql:

```bash
psql "$DATABASE_URL" -f transfer_ownership.sql
```

---

## Directory Structure

```
scripts/
  run-services.sh          # Start/stop/restart/status for all services
  build-services.sh        # Build one, many, or all services
  setup_db_users.sh        # DB user setup wrapper
  setup_db_users.sql       # DB user creation SQL
  grant_permissions.sql    # DB permission grants
  transfer_ownership.sql   # DB ownership transfer
  README.md                # This file
```

## Generated Directories

These are created automatically and should be gitignored:

```
../logs/services/          # Runtime service logs (from run-services.sh)
../logs/builds/            # Build logs (from build-services.sh)
../tmp/pids/               # PID files for running services
```
