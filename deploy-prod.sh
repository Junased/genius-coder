#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Simple production deploy
# =========================
# Default flow:
#   1. Backup PostgreSQL data
#   2. Pull latest code
#   3. Rebuild new-api image
#   4. Recreate only the new-api container
#   5. Check health URL
#
# Example:
#   BRANCH=main HEALTH_URL=https://www.geniuscoder.cn/api/status ./deploy-prod.sh

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BRANCH="${BRANCH:-main}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-}"
APP_SERVICE="${APP_SERVICE:-new-api}"
DB_CONTAINER="${DB_CONTAINER:-postgres}"
DB_USER="${DB_USER:-root}"
DB_NAME="${DB_NAME:-new-api}"
BACKUP_DIR="${BACKUP_DIR:-/opt/genius-coder-data-backup}"
HEALTH_URL="${HEALTH_URL:-https://www.geniuscoder.cn/api/status}"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-60}"
RUN_DB_BACKUP="${RUN_DB_BACKUP:-true}"

cd "$REPO_DIR"

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

compose() {
  if docker compose version >/dev/null 2>&1; then
    if [[ -n "$COMPOSE_PROJECT" ]]; then
      docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" "$@"
    else
      docker compose -f "$COMPOSE_FILE" "$@"
    fi
  elif command -v docker-compose >/dev/null 2>&1; then
    if [[ -n "$COMPOSE_PROJECT" ]]; then
      docker-compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" "$@"
    else
      docker-compose -f "$COMPOSE_FILE" "$@"
    fi
  else
    die "Missing command: docker compose or docker-compose"
  fi
}

backup_database() {
  if [[ "$RUN_DB_BACKUP" != "true" ]]; then
    log "Skipping database backup because RUN_DB_BACKUP=$RUN_DB_BACKUP"
    return
  fi

  need_cmd docker
  need_cmd gzip

  if [[ -z "$(docker ps --filter "name=^/${DB_CONTAINER}$" --filter status=running -q)" ]]; then
    die "Database container '$DB_CONTAINER' is not running. Set DB_CONTAINER or run with RUN_DB_BACKUP=false."
  fi

  mkdir -p "$BACKUP_DIR"

  local backup_file
  backup_file="$BACKUP_DIR/${DB_NAME}-$(date +%Y%m%d-%H%M%S).sql.gz"

  log "Backing up PostgreSQL database to $backup_file"
  if ! docker exec -i "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip >"$backup_file"; then
    rm -f "$backup_file"
    die "Database backup failed"
  fi

  gzip -t "$backup_file"
  log "Database backup complete"
}

pull_latest_code() {
  need_cmd git

  log "Pulling latest code from $GIT_REMOTE/$BRANCH"
  git fetch "$GIT_REMOTE" "$BRANCH"
  git checkout "$BRANCH"
  git pull --ff-only "$GIT_REMOTE" "$BRANCH"
}

build_app() {
  [[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"

  log "Building service with no cache: $APP_SERVICE"
  compose build --no-cache "$APP_SERVICE"
}

restart_app() {
  log "Recreating service: $APP_SERVICE"
  compose up -d --force-recreate --no-deps "$APP_SERVICE"
}

wait_for_health() {
  need_cmd curl

  log "Checking health: $HEALTH_URL"
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))
  until curl -f "$HEALTH_URL" >/dev/null; do
    if ((SECONDS >= deadline)); then
      compose logs --tail=120 "$APP_SERVICE" || true
      die "Health check failed after ${HEALTH_TIMEOUT_SECONDS}s"
    fi
    sleep 2
  done

  log "Health check passed"
}

deploy() {
  backup_database
  pull_latest_code
  build_app
  restart_app
  wait_for_health

  log "Production deploy finished"
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  help | --help | -h)
    cat <<USAGE
Usage:
  ./deploy-prod.sh

Settings:
  REPO_DIR=$REPO_DIR
  BRANCH=$BRANCH
  GIT_REMOTE=$GIT_REMOTE
  COMPOSE_FILE=$COMPOSE_FILE
  COMPOSE_PROJECT=<old compose project name, optional>
  APP_SERVICE=$APP_SERVICE
  DB_CONTAINER=$DB_CONTAINER
  DB_USER=$DB_USER
  DB_NAME=$DB_NAME
  BACKUP_DIR=$BACKUP_DIR
  HEALTH_URL=$HEALTH_URL
  HEALTH_TIMEOUT_SECONDS=$HEALTH_TIMEOUT_SECONDS
  RUN_DB_BACKUP=true|false

Examples:
  BRANCH=main HEALTH_URL=https://www.geniuscoder.cn/api/status ./deploy-prod.sh
  RUN_DB_BACKUP=false ./deploy-prod.sh
USAGE
    ;;
  *)
    die "Unknown command: $1. Run ./deploy-prod.sh help"
    ;;
esac
