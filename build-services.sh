#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# build-services.sh — Build one, many, or all LMS services
#
# Usage:
#   ./build-services.sh                     Build ALL services (backend + frontend)
#   ./build-services.sh user-service        Build a single service
#   ./build-services.sh user-service login-service   Build multiple services
#   ./build-services.sh --backend           Build all backend services only
#   ./build-services.sh --frontend          Build frontend (algoristics) only
#   ./build-services.sh --install           Run npm install before building
#   ./build-services.sh --clean             Remove .next/dist build artifacts before building
#   ./build-services.sh --parallel          Build services in parallel (faster, noisier logs)
#
# Flags can be combined:
#   ./build-services.sh --install --clean user-service login-service
#   ./build-services.sh --backend --install --parallel
#   ./build-services.sh --clean --parallel
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Service Registry ─────────────────────────────────────────────────────────

BACKEND_SERVICES=(
  docs-service
  user-service
  organization-service
  course-service
  assessment-service
  analytics-service
  storage-service
  dashboard-service
  public-service
  login-service
  logging-service
  learning-paths-service
  rubric-service
  assignment-service
  notification-service
  code-editor-service
  proctoring-service
  ai-service
)

FRONTEND_SERVICE="algoristics"

# ── Colors & Formatting ──────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${CYAN}[info]${NC}  $1"; }
log_ok()      { echo -e "${GREEN}[done]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[warn]${NC}  $1"; }
log_err()     { echo -e "${RED}[fail]${NC}  $1"; }
log_header()  { echo -e "\n${BOLD}$1${NC}"; }

# ── Build Log Directory ──────────────────────────────────────────────────────

BUILD_LOG_DIR="$ROOT_DIR/logs/builds"
mkdir -p "$BUILD_LOG_DIR"

# ── Parse Arguments ──────────────────────────────────────────────────────────

DO_INSTALL=false
DO_CLEAN=false
DO_PARALLEL=false
BUILD_BACKEND=false
BUILD_FRONTEND=false
SPECIFIC_SERVICES=()

for arg in "$@"; do
  case "$arg" in
    --install)   DO_INSTALL=true ;;
    --clean)     DO_CLEAN=true ;;
    --parallel)  DO_PARALLEL=true ;;
    --backend)   BUILD_BACKEND=true ;;
    --frontend)  BUILD_FRONTEND=true ;;
    --help|-h)
      echo "Usage: $(basename "$0") [flags] [service-name ...]"
      echo ""
      echo "Build one, many, or all LMS services."
      echo ""
      echo "Flags:"
      echo "  --install     Run npm install before building each service"
      echo "  --clean       Remove build artifacts (.next / dist) before building"
      echo "  --parallel    Build services concurrently (faster, mixed log output)"
      echo "  --backend     Build all backend services (Next.js)"
      echo "  --frontend    Build frontend only (algoristics / Vite)"
      echo "  --help, -h    Show this help message"
      echo ""
      echo "Examples:"
      echo "  $(basename "$0")                                   # Build everything"
      echo "  $(basename "$0") user-service                      # Build one service"
      echo "  $(basename "$0") user-service login-service        # Build two services"
      echo "  $(basename "$0") --backend --install --parallel    # Install + build all backend in parallel"
      echo "  $(basename "$0") --clean --frontend                # Clean build the frontend"
      exit 0
      ;;
    -*)
      log_err "Unknown flag: $arg (use --help for usage)"
      exit 1
      ;;
    *)
      SPECIFIC_SERVICES+=("$arg")
      ;;
  esac
done

# ── Resolve What to Build ────────────────────────────────────────────────────

TARGETS=()

if [ ${#SPECIFIC_SERVICES[@]} -gt 0 ]; then
  # User specified exact services — validate each one
  ALL_KNOWN=("${BACKEND_SERVICES[@]}" "$FRONTEND_SERVICE")
  for svc in "${SPECIFIC_SERVICES[@]}"; do
    found=false
    for known in "${ALL_KNOWN[@]}"; do
      if [ "$svc" = "$known" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = true ]; then
      TARGETS+=("$svc")
    else
      log_err "Unknown service: $svc"
      log_info "Available services: ${ALL_KNOWN[*]}"
      exit 1
    fi
  done
elif [ "$BUILD_BACKEND" = true ] || [ "$BUILD_FRONTEND" = true ]; then
  # User specified category flags
  if [ "$BUILD_BACKEND" = true ]; then
    TARGETS+=("${BACKEND_SERVICES[@]}")
  fi
  if [ "$BUILD_FRONTEND" = true ]; then
    TARGETS+=("$FRONTEND_SERVICE")
  fi
else
  # No args — build everything
  TARGETS+=("${BACKEND_SERVICES[@]}")
  TARGETS+=("$FRONTEND_SERVICE")
fi

# ── Build Functions ──────────────────────────────────────────────────────────

build_node_service() {
  local name="$1"
  local svc_dir="$ROOT_DIR/$name"
  local log_file="$BUILD_LOG_DIR/$name.build.log"
  local start_time
  start_time=$(date +%s)

  if [ ! -d "$svc_dir" ]; then
    log_err "$name — directory not found at $svc_dir"
    return 1
  fi

  if [ ! -f "$svc_dir/package.json" ]; then
    log_err "$name — no package.json found"
    return 1
  fi

  # Check that a build script exists
  if ! (cd "$svc_dir" && npm run 2>/dev/null | grep -q "build"); then
    log_err "$name — no 'build' script in package.json"
    return 1
  fi

  log_info "$name — building..."

  (
    cd "$svc_dir"

    # Clean build artifacts if requested
    if [ "$DO_CLEAN" = true ]; then
      if [ -d ".next" ]; then
        rm -rf .next
        log_info "$name — cleaned .next"
      fi
      if [ -d "dist" ]; then
        rm -rf dist
        log_info "$name — cleaned dist"
      fi
    fi

    # Install dependencies if requested
    if [ "$DO_INSTALL" = true ]; then
      log_info "$name — installing dependencies..."
      if ! npm install >>"$log_file" 2>&1; then
        log_err "$name — npm install failed (see $log_file)"
        return 1
      fi
    fi

    # Run build
    if npm run build >>"$log_file" 2>&1; then
      local end_time
      end_time=$(date +%s)
      local duration=$((end_time - start_time))
      log_ok "$name — built in ${duration}s"
      return 0
    else
      local end_time
      end_time=$(date +%s)
      local duration=$((end_time - start_time))
      log_err "$name — build failed after ${duration}s (see $log_file)"
      return 1
    fi
  )
}


# ── Execute Builds ───────────────────────────────────────────────────────────

TOTAL=${#TARGETS[@]}
SUCCEEDED=0
FAILED=0
FAILED_LIST=()

log_header "Building $TOTAL service(s)..."

if [ "$DO_INSTALL" = true ]; then
  log_info "Flag: --install (npm install before build)"
fi
if [ "$DO_CLEAN" = true ]; then
  log_info "Flag: --clean (remove build artifacts first)"
fi
if [ "$DO_PARALLEL" = true ]; then
  log_info "Flag: --parallel (concurrent builds)"
fi

echo ""

if [ "$DO_PARALLEL" = true ]; then
  # ── Parallel Build ───────────────────────────────────────────────────────
  PIDS=()
  PID_NAMES=()

  for svc in "${TARGETS[@]}"; do
    build_node_service "$svc" &
    PIDS+=($!)
    PID_NAMES+=("$svc")
  done

  # Wait for all and collect results
  for i in "${!PIDS[@]}"; do
    if wait "${PIDS[$i]}"; then
      SUCCEEDED=$((SUCCEEDED + 1))
    else
      FAILED=$((FAILED + 1))
      FAILED_LIST+=("${PID_NAMES[$i]}")
    fi
  done
else
  # ── Sequential Build ─────────────────────────────────────────────────────
  for svc in "${TARGETS[@]}"; do
    if build_node_service "$svc"; then
      SUCCEEDED=$((SUCCEEDED + 1))
    else
      FAILED=$((FAILED + 1))
      FAILED_LIST+=("$svc")
    fi
  done
fi

# ── Summary ──────────────────────────────────────────────────────────────────

log_header "Build Summary"
echo ""
echo -e "  Total:     $TOTAL"
echo -e "  ${GREEN}Succeeded:${NC} $SUCCEEDED"

if [ "$FAILED" -gt 0 ]; then
  echo -e "  ${RED}Failed:${NC}    $FAILED"
  echo ""
  log_err "Failed services:"
  for svc in "${FAILED_LIST[@]}"; do
    echo -e "    - $svc (log: $BUILD_LOG_DIR/$svc.build.log)"
  done
  echo ""
  exit 1
else
  echo -e "  ${RED}Failed:${NC}    0"
  echo ""
  log_ok "All builds passed."
fi
