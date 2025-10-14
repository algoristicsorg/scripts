#!/bin/bash

# Manage all LMS services in dev mode with DATABASE_URL set

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="postgresql://_8f5cae57941ad7f3:_c4f65765b475d16620a0aacfa9efce@primary.algoristics-db-dev--8grzfnjvvk8s.addon.code.run:27958/_212cc58bf63c?sslmode=require"
JWT_SECRET_VALUE="${JWT_SECRET:-dev_jwt_secret_change_me}"

# List of services and ports (portable for macOS bash 3.x)
SERVICES="
docs-service 4000
user-service 4001
organization-service 4002
course-service 4003
assessment-service 4004
analytics-service 4005
storage-service 4006
dashboard-service 4008
public-service 4007
login-service 4009
logging-service 4010
"

log_dir="$ROOT_DIR/logs/services"
pid_dir="$ROOT_DIR/tmp/pids"
mkdir -p "$log_dir" "$pid_dir"

build_service() {
  local name="$1"
  local svc_dir="$ROOT_DIR/services/$name"

  if [ ! -d "$svc_dir" ]; then
    echo "[error] $name directory not found at $svc_dir" >&2
    return 1
  fi

  echo "[check] $name"
  (
    cd "$svc_dir"
    # Check if package.json exists and has required scripts
    if [ ! -f "package.json" ]; then
      echo "[warning] $name has no package.json" >&2
      return 1
    fi
    
    # Check if dev script exists (required for Next.js services)
    if ! npm run | grep -q "dev$"; then
      echo "[warning] $name has no dev script" >&2
      return 1
    fi
    
    echo "[ready] $name"
  )
}

build_all_services() {
  echo "Checking all services..."
  local failed_services=""
  echo "$SERVICES" | while read -r name port; do
    [ -z "${name:-}" ] && continue
    if ! build_service "$name"; then
      failed_services="$failed_services $name"
    fi
  done
  
  if [ -n "$failed_services" ]; then
    echo "[warning] Some services had issues:$failed_services"
  fi
  echo "Check phase completed."
}

start_service() {
  local name="$1"
  local port="$2"
  local svc_dir="$ROOT_DIR/services/$name"
  local log_file="$log_dir/$name.log"
  local pid_file="$pid_dir/$name.dev.pid"

  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[skip] $name: port $port already in use"
    return 0
  fi

  if [ ! -d "$svc_dir" ]; then
    echo "[error] $name directory not found at $svc_dir" >&2
    return 1
  fi

  echo "[start] $name on :$port"
  (
    cd "$svc_dir"
    JWT_SECRET="$JWT_SECRET_VALUE" DATABASE_URL="$DB_URL" \
    MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}" \
    MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-${MINIO_ROOT_USER:-admin}}" \
    MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-${MINIO_ROOT_PASSWORD:-admin12345}}" \
    npm run dev >>"$log_file" 2>&1 &
    echo $! >"$pid_file"
  )
}

stop_service() {
  local name="$1"
  local port="$2"
  local pid_file="$pid_dir/$name.dev.pid"
  local pids=""

  # Prefer PID file if present
  if [ -f "$pid_file" ]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || echo "")"
    if [ -n "${pid}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "[stop] $name (pid $pid)"
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi

  # Also kill by port (covers processes started outside this script)
  pids="$(lsof -t -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "${pids}" ]; then
    echo "[stop] $name by port :$port (pids: $pids)"
    echo "$pids" | xargs -I {} kill {} >/dev/null 2>&1 || true
  fi

  # Wait for port to be freed, then cleanup
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      sleep 0.3
    else
      break
    fi
  done

  # Force kill if still listening
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    pids="$(lsof -t -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
    if [ -n "${pids}" ]; then
      echo "[kill] $name still listening on :$port; sending SIGKILL"
      echo "$pids" | xargs -I {} kill -9 {} >/dev/null 2>&1 || true
    fi
  fi

  # Remove stale pid file
  rm -f "$pid_file" 2>/dev/null || true
}

wait_for_service() {
  local name="$1"
  local port="$2"
  local timeout=30
  local count=0
  
  while [ $count -lt $timeout ]; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    count=$((count + 1))
  done
  return 1
}

status_services() {
  echo "\nSummary:"
  echo "$SERVICES" | while read -r name port; do
    [ -z "${name:-}" ] && continue
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo " - $name listening on http://localhost:$port"
    else
      echo " - $name not listening (check logs/services/$name.log)"
    fi
  done
  echo "\nLogs: $log_dir"
  echo "PIDs:  $pid_dir"
}

cmd="${1:-start}"
case "$cmd" in
  start)
    build_all_services
    echo "Starting LMS services..."
    echo "$SERVICES" | while read -r name port; do
      [ -z "${name:-}" ] && continue
      start_service "$name" "$port"
    done
    
    echo "Waiting for services to be ready..."
    echo "$SERVICES" | while read -r name port; do
      [ -z "${name:-}" ] && continue
      if wait_for_service "$name" "$port"; then
        echo " - $name ready on http://localhost:$port"
      else
        echo " - $name failed to start (check logs/services/$name.log)"
      fi
    done
    
    status_services
    ;;
  stop)
    echo "Stopping LMS services..."
    echo "$SERVICES" | while read -r name port; do
      [ -z "${name:-}" ] && continue
      stop_service "$name" "$port"
    done
    status_services
    ;;
  build)
    build_all_services
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  status)
    status_services
    ;;
  *)
    echo "Usage: $(basename "$0") {start|stop|restart|build|status}" >&2
    exit 1
    ;;
esac

