#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-new-api}"
PORT="${PORT:-3000}"
PID_FILE="${PID_FILE:-$ROOT_DIR/.run/${APP_NAME}.pid}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/logs/${APP_NAME}.log}"
MODE="${1:-local}"

VERSION="$(cat "$ROOT_DIR/VERSION")"
GO_LDFLAGS="-s -w -X github.com/QuantumNous/new-api/common.Version=${VERSION}"

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

build_frontends() {
  need_cmd bun

  log "Installing frontend dependencies"
  (cd "$ROOT_DIR/web" && bun install --frozen-lockfile)

  log "Building default frontend"
  (
    cd "$ROOT_DIR/web/default"
    DISABLE_ESLINT_PLUGIN=true VITE_REACT_APP_VERSION="$VERSION" bun run build
  )

  log "Building classic frontend"
  (
    cd "$ROOT_DIR/web/classic"
    VITE_REACT_APP_VERSION="$VERSION" bun run build
  )
}

build_backend() {
  need_cmd go

  log "Building backend binary"
  go build -ldflags "$GO_LDFLAGS" -o "$ROOT_DIR/$APP_NAME"
}

stop_local_backend() {
  if [[ ! -f "$PID_FILE" ]]; then
    return
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    log "Stopping existing backend process: $pid"
    kill "$pid"
    for _ in {1..30}; do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        break
      fi
      sleep 0.2
    done
  fi
  rm -f "$PID_FILE"
}

start_local_backend() {
  mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"

  log "Starting backend on port $PORT"
  PORT="$PORT" "$ROOT_DIR/$APP_NAME" >>"$LOG_FILE" 2>&1 &
  echo "$!" >"$PID_FILE"

  log "Backend pid: $(cat "$PID_FILE")"
  log "Backend log: $LOG_FILE"
}

wait_for_health() {
  if ! command -v curl >/dev/null 2>&1; then
    log "curl not found, skipping health check"
    return
  fi

  local url="http://127.0.0.1:${PORT}/api/status"
  log "Waiting for $url"
  for _ in {1..40}; do
    if curl --fail --silent "$url" >/dev/null 2>&1; then
      log "Deployment ready: http://127.0.0.1:${PORT}"
      return
    fi
    sleep 0.5
  done

  die "Backend did not become healthy. Check: $LOG_FILE"
}

deploy_local() {
  build_frontends
  build_backend
  stop_local_backend
  start_local_backend
  wait_for_health
}

deploy_dev_stack() {
  need_cmd docker
  need_cmd bun

  log "Building frontend assets"
  build_frontends

  log "Rebuilding and starting development backend stack"
  docker compose -f "$ROOT_DIR/docker-compose.dev.yml" up -d --build new-api

  log "Development backend is on http://127.0.0.1:3000"
  log "To run the classic frontend dev server: make dev-web-classic"
}

deploy_docker() {
  need_cmd docker

  local image="${DOCKER_IMAGE:-genius-coder-local:latest}"
  local container="${DOCKER_CONTAINER:-genius-coder-local}"
  local data_dir="${DOCKER_DATA_DIR:-$ROOT_DIR/data}"
  local logs_dir="${DOCKER_LOG_DIR:-$ROOT_DIR/logs}"

  mkdir -p "$data_dir" "$logs_dir"

  log "Building Docker image: $image"
  docker build -t "$image" "$ROOT_DIR"

  if docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
    log "Removing existing container: $container"
    docker rm -f "$container" >/dev/null
  fi

  log "Starting Docker container: $container"
  docker run -d \
    --name "$container" \
    --restart unless-stopped \
    -p "${PORT}:3000" \
    -v "$data_dir:/data" \
    -v "$logs_dir:/app/logs" \
    -e TZ="${TZ:-Asia/Shanghai}" \
    "$image" \
    --log-dir /app/logs

  log "Docker deployment ready: http://127.0.0.1:${PORT}"
}

case "$MODE" in
  local)
    deploy_local
    ;;
  dev)
    deploy_dev_stack
    ;;
  docker)
    deploy_docker
    ;;
  *)
    cat <<USAGE
Usage:
  ./deploy-local.sh          Build both frontends, build backend, restart local binary
  ./deploy-local.sh local    Same as default
  ./deploy-local.sh dev      Build frontends and rebuild docker-compose.dev backend
  ./deploy-local.sh docker   Build full Docker image and restart local container

Environment:
  PORT=3000
  APP_NAME=new-api
  PID_FILE=.run/new-api.pid
  LOG_FILE=logs/new-api.log
  DOCKER_IMAGE=genius-coder-local:latest
  DOCKER_CONTAINER=genius-coder-local
USAGE
    exit 2
    ;;
esac
