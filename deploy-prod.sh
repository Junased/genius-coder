#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Production deploy settings
# =========================
# You can edit these defaults, or override them per run:
#   BRANCH=main HEALTH_URL=https://api.example.com/api/status ./deploy-prod.sh

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BRANCH="${BRANCH:-}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
APP_SERVICE="${APP_SERVICE:-new-api}"
DB_SERVICE="${DB_SERVICE:-postgres}"
REDIS_SERVICE="${REDIS_SERVICE:-redis}"
APP_CONTAINER="${APP_CONTAINER:-$APP_SERVICE}"
DB_CONTAINER="${DB_CONTAINER:-$DB_SERVICE}"
REDIS_CONTAINER="${REDIS_CONTAINER:-$REDIS_SERVICE}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-}"
AUTO_DETECT_COMPOSE_PROJECT="${AUTO_DETECT_COMPOSE_PROJECT:-true}"
DB_USER="${DB_USER:-root}"
DB_NAME="${DB_NAME:-new-api}"
IMAGE="${IMAGE:-calciumion/new-api:latest}"
DOCKER_BUILD_PROGRESS="${DOCKER_BUILD_PROGRESS:-plain}"
DOCKER_BUILD_NO_CACHE="${DOCKER_BUILD_NO_CACHE:-false}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/api/status}"
BACKUP_DIR="/opt/genius-coder-data-backup"
RUN_GIT_PULL="${RUN_GIT_PULL:-true}"
RUN_DB_BACKUP="${RUN_DB_BACKUP:-true}"
START_DEPENDENCIES="${START_DEPENDENCIES:-true}"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-60}"

cd "$REPO_DIR"

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

running_container_id() {
  docker ps --filter "name=^/$1$" --filter "status=running" -q | head -n 1
}

container_compose_project() {
  docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$1" 2>/dev/null || true
}

detect_compose_project() {
  if [[ -n "$COMPOSE_PROJECT" ]]; then
    printf '%s' "$COMPOSE_PROJECT"
    return
  fi

  if [[ "$AUTO_DETECT_COMPOSE_PROJECT" != "true" ]]; then
    return
  fi

  local container project
  for container in "$APP_CONTAINER" "$DB_CONTAINER" "$REDIS_CONTAINER"; do
    project="$(container_compose_project "$container")"
    if [[ -n "$project" && "$project" != "<no value>" ]]; then
      printf '%s' "$project"
      return
    fi
  done
}

compose() {
  local project
  local project_args=()
  project="$(detect_compose_project)"
  if [[ -n "$project" ]]; then
    project_args=(-p "$project")
  fi

  if docker compose version >/dev/null 2>&1; then
    docker compose "${project_args[@]}" -f "$COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "${project_args[@]}" -f "$COMPOSE_FILE" "$@"
  else
    die "Missing command: docker compose or docker-compose"
  fi
}

current_branch() {
  git rev-parse --abbrev-ref HEAD
}

resolve_branch() {
  if [[ -n "$BRANCH" ]]; then
    printf '%s' "$BRANCH"
    return
  fi
  current_branch
}

assert_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    die "Git worktree is not clean. Commit/stash local changes before production deploy."
  fi
}

pull_latest_code() {
  if [[ "$RUN_GIT_PULL" != "true" ]]; then
    log "Skipping git pull because RUN_GIT_PULL=$RUN_GIT_PULL"
    return
  fi

  need_cmd git
  assert_clean_worktree

  local branch
  branch="$(resolve_branch)"
  log "Pulling latest code from origin/$branch"
  git fetch origin "$branch"
  git checkout "$branch"
  git pull --ff-only origin "$branch"
}

backup_database() {
  if [[ "$RUN_DB_BACKUP" != "true" ]]; then
    log "Skipping database backup because RUN_DB_BACKUP=$RUN_DB_BACKUP"
    return
  fi

  need_cmd docker
  need_cmd gzip
  mkdir -p "$BACKUP_DIR"

  local container_id
  container_id="$(compose ps -q "$DB_SERVICE" 2>/dev/null || true)"

  local backup_file
  backup_file="$BACKUP_DIR/${DB_NAME}-$(date +%Y%m%d-%H%M%S).sql.gz"

  log "Backing up PostgreSQL database to $backup_file"
  if [[ -n "$container_id" ]]; then
    compose exec -T "$DB_SERVICE" pg_dump -U "$DB_USER" "$DB_NAME" | gzip >"$backup_file"
  else
    container_id="$(running_container_id "$DB_CONTAINER" || true)"
    if [[ -z "$container_id" ]]; then
      die "Database service '$DB_SERVICE' or container '$DB_CONTAINER' is not running. Start it first or run with RUN_DB_BACKUP=false for first deploy."
    fi
    warn "Compose cannot see service '$DB_SERVICE'; backing up running container '$DB_CONTAINER' directly."
    docker exec -i "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip >"$backup_file"
  fi
  log "Database backup complete"
}

build_image() {
  need_cmd docker
  [[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"

  local build_args
  build_args=(--progress="$DOCKER_BUILD_PROGRESS" -t "$IMAGE")
  if [[ "$DOCKER_BUILD_NO_CACHE" == "true" ]]; then
    build_args=(--no-cache "${build_args[@]}")
  fi

  log "Building Docker image from current source: $IMAGE"
  docker build "${build_args[@]}" "$REPO_DIR"
}

start_dependencies() {
  if [[ "$START_DEPENDENCIES" != "true" ]]; then
    log "Skipping dependency startup because START_DEPENDENCIES=$START_DEPENDENCIES"
    return
  fi

  log "Starting dependencies: $DB_SERVICE $REDIS_SERVICE"
  start_dependency "$DB_SERVICE" "$DB_CONTAINER"
  start_dependency "$REDIS_SERVICE" "$REDIS_CONTAINER"
}

start_dependency() {
  local service="$1"
  local container="$2"

  if [[ -n "$(compose ps -q "$service" 2>/dev/null || true)" ]]; then
    compose up -d "$service"
    return
  fi

  if [[ -n "$(running_container_id "$container" || true)" ]]; then
    log "Dependency container already running: $container"
    return
  fi

  compose up -d "$service"
}

restart_app() {
  log "Recreating application service: $APP_SERVICE"
  if [[ -z "$(compose ps -q "$APP_SERVICE" 2>/dev/null || true)" ]] &&
    docker ps -a --filter "name=^/$APP_CONTAINER$" -q | grep -q .; then
    die "Application container '$APP_CONTAINER' exists but is not managed by this compose project. Set COMPOSE_PROJECT to the old compose project name, or stop/remove only this app container manually before deploying."
  fi
  compose up -d --force-recreate "$APP_SERVICE"
}

wait_for_health() {
  need_cmd curl

  log "Waiting for health check: $HEALTH_URL"
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))
  until curl --fail --silent "$HEALTH_URL" >/dev/null; do
    if (( SECONDS >= deadline )); then
      warn "Health check failed. Recent app logs:"
      compose logs --tail=120 "$APP_SERVICE" || true
      die "Deployment failed health check after ${HEALTH_TIMEOUT_SECONDS}s"
    fi
    sleep 2
  done

  log "Deployment healthy: $HEALTH_URL"
}

show_summary() {
  log "Running services"
  compose ps
}

deploy() {
  local old_rev new_rev
  old_rev="$(git rev-parse --short HEAD 2>/dev/null || true)"

  pull_latest_code
  new_rev="$(git rev-parse --short HEAD 2>/dev/null || true)"

  log "Deploying revision: ${new_rev:-unknown} (previous: ${old_rev:-unknown})"
  backup_database
  build_image
  start_dependencies
  restart_app
  wait_for_health
  show_summary

  log "Production deploy finished"
}

rollback() {
  need_cmd git
  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: ./deploy-prod.sh rollback <commit-or-tag>"

  assert_clean_worktree
  log "Rolling back code to $target"
  git checkout "$target"

  RUN_GIT_PULL=false deploy
}

case "${1:-deploy}" in
  deploy)
    deploy
    ;;
  rollback)
    rollback "${2:-}"
    ;;
  help|--help|-h)
    cat <<USAGE
Usage:
  ./deploy-prod.sh
  ./deploy-prod.sh deploy
  ./deploy-prod.sh rollback <commit-or-tag>

Common settings:
  REPO_DIR=$REPO_DIR
  BRANCH=<production branch, default: current branch>
  COMPOSE_FILE=$COMPOSE_FILE
  APP_SERVICE=$APP_SERVICE
  DB_SERVICE=$DB_SERVICE
  REDIS_SERVICE=$REDIS_SERVICE
  APP_CONTAINER=$APP_CONTAINER
  DB_CONTAINER=$DB_CONTAINER
  REDIS_CONTAINER=$REDIS_CONTAINER
  COMPOSE_PROJECT=<optional old compose project name>
  DB_USER=$DB_USER
  DB_NAME=$DB_NAME
  IMAGE=$IMAGE
  DOCKER_BUILD_PROGRESS=$DOCKER_BUILD_PROGRESS
  DOCKER_BUILD_NO_CACHE=true|false
  HEALTH_URL=$HEALTH_URL
  RUN_DB_BACKUP=true|false
  RUN_GIT_PULL=true|false

Examples:
  BRANCH=main HEALTH_URL=https://www.geniuscoder.cn/api/status ./deploy-prod.sh
  RUN_DB_BACKUP=false ./deploy-prod.sh
  ./deploy-prod.sh rollback v1.2.3
USAGE
    ;;
  *)
    die "Unknown command: $1. Run ./deploy-prod.sh help"
    ;;
esac
