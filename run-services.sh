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
dashboard-service 4007
public-service 4008
login-service 4009
logging-service 4010
learning-paths-service 4011
rubric-service 4012
assignment-service 4013
notification-service 4014
code-editor-service 4015
proctoring-service 4016
"

# Python-based service (runs separately via run.sh / Podman)
CEE_SERVICE="code-execution-engine"
CEE_PORT=8000

log_dir="$ROOT_DIR/logs/services"
pid_dir="$ROOT_DIR/tmp/pids"
mkdir -p "$log_dir" "$pid_dir"

build_service() {
  local name="$1"
  local svc_dir="$ROOT_DIR/$name"

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
  local svc_dir="$ROOT_DIR/$name"
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
  echo "\n🚀 LMS Services Status:"
  echo "$SERVICES" | while read -r name port; do
    [ -z "${name:-}" ] && continue
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      case "$name" in
        "docs-service")
          echo " ✅ $name - Swagger UI & API Docs: http://localhost:$port/api/docs"
          ;;
        "organization-service")
          echo " ✅ $name - Organizations API: http://localhost:$port/api/organizations"
          ;;
        "user-service")
          echo " ✅ $name - Users API: http://localhost:$port/api/users"
          ;;
        "course-service")
          echo " ✅ $name - Courses API: http://localhost:$port/api/courses"
          ;;
        "assessment-service")
          echo " ✅ $name - Assessments API: http://localhost:$port/api/assessments"
          ;;
        "public-service")
          echo " ✅ $name - Public APIs: http://localhost:$port/api/courses"
          ;;
        "analytics-service")
          echo " ✅ $name - Analytics APIs: http://localhost:$port/api/overview"
          ;;
        "login-service")
          echo " ✅ $name - Authentication API: http://localhost:$port/api/auth/login"
          ;;
        "rubric-service")
          echo " ✅ $name - Rubrics API: http://localhost:$port/api/rubrics"
          ;;
        "assignment-service")
          echo " ✅ $name - Assignments API: http://localhost:$port/api/assignments"
          ;;
        "notification-service")
          echo " ✅ $name - Notifications API: http://localhost:$port/api/notifications"
          ;;
        "code-editor-service")
          echo " ✅ $name - Code Editor API: http://localhost:$port/api/code-editor"
          ;;
        *)
          echo " ✅ $name - Service API: http://localhost:$port"
          ;;
      esac
    else
      echo " ❌ $name not listening (check logs/services/$name.log)"
    fi
  done

  # Check code-execution-engine separately (Python service)
  if lsof -nP -iTCP:"$CEE_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo " ✅ $CEE_SERVICE - Execution API: http://localhost:$CEE_PORT/docs"
  else
    echo " ❌ $CEE_SERVICE not listening on :$CEE_PORT (start separately via run.sh)"
  fi

  echo "\n📊 Quick Access:"
  if lsof -nP -iTCP:4000 -sTCP:LISTEN >/dev/null 2>&1; then
    echo " 🌐 Swagger UI: http://localhost:4000/api/docs"
  fi
  if lsof -nP -iTCP:4009 -sTCP:LISTEN >/dev/null 2>&1; then
    echo " 🔐 Test Login: curl -X POST http://localhost:4009/api/auth/login -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"admin123\"}'"
  fi
  
  if lsof -nP -iTCP:"$CEE_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo " 🖥️  Code Execution: http://localhost:$CEE_PORT/docs"
  fi

  echo "\n📁 Debug Info:"
  echo " 📋 Logs: $log_dir"
  echo " 🔧 PIDs:  $pid_dir"
}

start_cee() {
  local svc_dir="$ROOT_DIR/$CEE_SERVICE"
  local log_file="$log_dir/$CEE_SERVICE.log"
  local pid_file="$pid_dir/$CEE_SERVICE.dev.pid"

  if lsof -nP -iTCP:"$CEE_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[skip] $CEE_SERVICE: port $CEE_PORT already in use"
    return 0
  fi

  if [ ! -d "$svc_dir" ]; then
    echo "[warn] $CEE_SERVICE directory not found — skipping (runs via Podman/Docker)"
    return 0
  fi

  # Check if run.sh exists (preferred start method)
  if [ -f "$svc_dir/run.sh" ]; then
    echo "[start] $CEE_SERVICE on :$CEE_PORT (via run.sh)"
    (
      cd "$svc_dir"
      bash run.sh dev >>"$log_file" 2>&1 &
      echo $! >"$pid_file"
    )
  else
    echo "[warn] $CEE_SERVICE has no run.sh — start manually via 'make dev' or Docker"
  fi
}

stop_cee() {
  local pid_file="$pid_dir/$CEE_SERVICE.dev.pid"

  if [ -f "$pid_file" ]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || echo "")"
    if [ -n "${pid}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "[stop] $CEE_SERVICE (pid $pid)"
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi

  local pids
  pids="$(lsof -t -nP -iTCP:"$CEE_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "${pids}" ]; then
    echo "[stop] $CEE_SERVICE by port :$CEE_PORT (pids: $pids)"
    echo "$pids" | xargs -I {} kill {} >/dev/null 2>&1 || true
  fi

  rm -f "$pid_file" 2>/dev/null || true
}

cmd="${1:-start}"
service_name="${2:-}"

case "$cmd" in
  start)
    if [ -n "$service_name" ]; then
      # Start specific service
      port=$(echo "$SERVICES" | grep "^$service_name " | awk '{print $2}')
      if [ -n "$port" ]; then
        echo "Starting $service_name..."
        build_service "$service_name"
        start_service "$service_name" "$port"
        if wait_for_service "$service_name" "$port"; then
          echo " ✅ $service_name ready on http://localhost:$port"
        else
          echo " ❌ $service_name failed to start (check logs/services/$service_name.log)"
        fi
      elif [ "$service_name" = "$CEE_SERVICE" ]; then
        echo "Starting $CEE_SERVICE..."
        start_cee
        if wait_for_service "$CEE_SERVICE" "$CEE_PORT"; then
          echo " ✅ $CEE_SERVICE ready - API docs: http://localhost:$CEE_PORT/docs"
        else
          echo " ⚠️  $CEE_SERVICE not ready (may need manual start via Podman/Docker)"
        fi
      else
        echo "[error] Unknown service: $service_name" >&2
        echo "Available services:"
        echo "$SERVICES" | awk '{if(NF) print "  - " $1}'
        echo "  - $CEE_SERVICE"
        exit 1
      fi
    else
      # Start all services
      build_all_services
      echo "Starting LMS services..."
      echo "$SERVICES" | while read -r name port; do
        [ -z "${name:-}" ] && continue
        start_service "$name" "$port"
      done

      # Start code-execution-engine (Python service)
      start_cee
    fi

    echo "⏳ Waiting for services to be ready..."
    echo "$SERVICES" | while read -r name port; do
      [ -z "${name:-}" ] && continue
      if wait_for_service "$name" "$port"; then
        case "$name" in
          "docs-service")
            echo " ✅ $name ready - Swagger UI: http://localhost:$port/api/docs"
            ;;
          "login-service")
            echo " ✅ $name ready - Auth API: http://localhost:$port/api/auth/login"
            ;;
          "rubric-service")
            echo " ✅ $name ready - Rubrics API: http://localhost:$port/api/rubrics"
            ;;
          "assignment-service")
            echo " ✅ $name ready - Assignments API: http://localhost:$port/api/assignments"
            ;;
          "notification-service")
            echo " ✅ $name ready - Notifications API: http://localhost:$port/api/notifications"
            ;;
          "code-editor-service")
            echo " ✅ $name ready - Code Editor API: http://localhost:$port/api/code-editor"
            ;;
          *)
            echo " ✅ $name ready on http://localhost:$port"
            ;;
        esac
      else
        echo " ❌ $name failed to start (check logs/services/$name.log)"
      fi
    done

    # Check code-execution-engine readiness
    if wait_for_service "$CEE_SERVICE" "$CEE_PORT"; then
      echo " ✅ $CEE_SERVICE ready - API docs: http://localhost:$CEE_PORT/docs"
    else
      echo " ⚠️  $CEE_SERVICE not ready (may need manual start via Podman/Docker)"
    fi

    status_services
    ;;
  stop)
    if [ -n "$service_name" ]; then
      # Stop specific service
      port=$(echo "$SERVICES" | grep "^$service_name " | awk '{print $2}')
      if [ -n "$port" ]; then
        echo "Stopping $service_name..."
        stop_service "$service_name" "$port"
        echo " ✅ $service_name stopped"
      elif [ "$service_name" = "$CEE_SERVICE" ]; then
        echo "Stopping $CEE_SERVICE..."
        stop_cee
        echo " ✅ $CEE_SERVICE stopped"
      else
        echo "[error] Unknown service: $service_name" >&2
        echo "Available services:"
        echo "$SERVICES" | awk '{if(NF) print "  - " $1}'
        echo "  - $CEE_SERVICE"
        exit 1
      fi
    else
      # Stop all services
      echo "Stopping LMS services..."
      echo "$SERVICES" | while read -r name port; do
        [ -z "${name:-}" ] && continue
        stop_service "$name" "$port"
      done
      stop_cee
    fi
    status_services
    ;;
  build)
    build_all_services
    ;;
  restart)
    if [ -n "$service_name" ]; then
      "$0" stop "$service_name"
      "$0" start "$service_name"
    else
      "$0" stop
      "$0" start
    fi
    ;;
  status)
    status_services
    ;;
  *)
    echo "Usage: $(basename "$0") {start|stop|restart|build|status} [service-name]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  start [service]   - Start all services or a specific service" >&2
    echo "  stop [service]    - Stop all services or a specific service" >&2
    echo "  restart [service] - Restart all services or a specific service" >&2
    echo "  build             - Check and build all services" >&2
    echo "  status            - Show status of all services" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $(basename "$0") start              # Start all services" >&2
    echo "  $(basename "$0") start user-service # Start only user-service" >&2
    echo "  $(basename "$0") stop user-service  # Stop only user-service" >&2
    echo "  $(basename "$0") restart login-service # Restart login-service" >&2
    echo "" >&2
    echo "Available services:" >&2
    echo "$SERVICES" | awk '{if(NF) print "  - " $1}' >&2
    echo "  - $CEE_SERVICE" >&2
    exit 1
    ;;
esac

