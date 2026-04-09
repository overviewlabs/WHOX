#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHOX_HOME="${WHOX_HOME:-$HOME/.whox}"
ENV_FILE="${WHOX_HOME}/.env"
CONFIG_FILE="${WHOX_HOME}/config.yaml"
REPO_ENV_FILE="${SCRIPT_DIR}/.env"
REPO_URL="${WHOX_REPO_URL:-https://github.com/overviewlabs/WHOX.git}"
INSTALL_SRC_DIR="${WHOX_INSTALL_SRC_DIR:-${WHOX_HOME}/src/WHOX}"
SETUP_DIR="$SCRIPT_DIR"
DEFAULT_MODEL="qwen/qwen3.5-397b-a17b"
DEFAULT_BASE_URL="https://integrate.api.nvidia.com/v1"
DEFAULT_TZ="America/New_York"
DEFAULT_DOMAIN=""
FIRECRAWL_REPO_URL="${WHOX_FIRECRAWL_REPO_URL:-https://github.com/mendableai/firecrawl.git}"
FIRECRAWL_DIR="${WHOX_FIRECRAWL_DIR:-$HOME/firecrawl}"
SNAPSHOT_DIR="${WHOX_SNAPSHOT_DIR:-$SCRIPT_DIR/snapshot}"
SNAPSHOT_RUNTIME_DIR="${SNAPSHOT_DIR}/runtime"
SNAPSHOT_FIRECRAWL_DIR="${SNAPSHOT_DIR}/firecrawl"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

banner() {
  clear || true
  cat <<'EOF'
$$\      $$\ $$\   $$\  $$$$$$\  $$\   $$\
$$ | $\  $$ |$$ |  $$ |$$  __$$\ $$ |  $$ |
$$ |$$$\ $$ |$$ |  $$ |$$ /  $$ |\$$\ $$  |
$$ $$ $$\$$ |$$$$$$$$ |$$ |  $$ | \$$$$  /
$$$$  _$$$$ |$$  __$$ |$$ |  $$ | $$  $$<
$$$  / \$$$ |$$ |  $$ |$$ |  $$ |$$  /\$$\
$$  /   \$$ |$$ |  $$ | $$$$$$  |$$ /  $$ |
\__/     \__|\__|  \__| \______/ \__|  \__|

WHOX Installer
EOF
  echo ""
}

prompt_required() {
  local label="$1"
  local secret="${2:-0}"
  local value=""
  while [[ -z "$value" ]]; do
    if [[ "$secret" == "1" ]]; then
      read -r -s -p "$label: " value
      echo ""
    else
      read -r -p "$label: " value
    fi
    value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  done
  printf "%s" "$value"
}

prompt_yes_no() {
  local label="$1"
  local default="${2:-y}"
  local suffix="y/N"
  local input=""
  if [[ "$default" == "y" ]]; then
    suffix="Y/n"
  fi
  while true; do
    read -r -p "${label} [${suffix}]: " input
    input="$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$input" ]]; then
      input="$default"
    fi
    case "$input" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
  done
}

install_prerequisites() {
  echo -e "${CYAN}Installing prerequisites...${NC}"
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Non-Linux host detected; skipping apt prerequisite bootstrap."
    return 0
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not available; skipping system prerequisite bootstrap."
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update -y >/dev/null
    if ! apt-get install -y ca-certificates curl git jq ripgrep python3.11 python3.11-venv >/dev/null 2>&1; then
      apt-get install -y ca-certificates curl git jq ripgrep python3 python3-venv >/dev/null 2>&1 || true
    fi
    # Docker stack is required by Firecrawl
    if ! command -v docker >/dev/null 2>&1; then
      if ! apt-get install -y docker.io docker-compose-plugin >/dev/null; then
        apt-get install -y docker.io docker-compose >/dev/null || true
      fi
      systemctl enable --now docker >/dev/null 2>&1 || true
    fi
  else
    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      sudo apt-get update -y >/dev/null
      if ! sudo apt-get install -y ca-certificates curl git jq ripgrep python3.11 python3.11-venv >/dev/null 2>&1; then
        sudo apt-get install -y ca-certificates curl git jq ripgrep python3 python3-venv >/dev/null 2>&1 || true
      fi
      if ! command -v docker >/dev/null 2>&1; then
        if ! sudo apt-get install -y docker.io docker-compose-plugin >/dev/null; then
          sudo apt-get install -y docker.io docker-compose >/dev/null || true
        fi
        sudo systemctl enable --now docker >/dev/null 2>&1 || true
      fi
    else
      echo "No root privileges; prerequisite install skipped (continuing with existing system packages)."
    fi
  fi
  echo "✓ Prerequisites checked"
}

firecrawl_http_code() {
  local path="$1"
  local code=""
  code="$(curl -sS --max-time 3 -o /dev/null -w "%{http_code}" "http://127.0.0.1:3002${path}" 2>/dev/null || true)"
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
    echo "000"
  else
    echo "$code"
  fi
}

upsert_env() {
  local file="$1"
  local key="$2"
  local val="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s#^${key}=.*#${key}=${val}#g" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

validate_telegram_token() {
  local token="$1"
  if [[ -z "$token" ]]; then
    echo "Telegram bot token is empty." >&2
    return 1
  fi
  local endpoint="https://api.telegram.org/bot${token}/getMe"
  local resp=""
  local code=""
  resp="$(curl -sS --max-time 20 -w $'\n%{http_code}' "$endpoint" 2>/dev/null || true)"
  code="$(echo "$resp" | tail -n1)"
  resp="$(echo "$resp" | sed '$d')"

  if [[ -z "$code" || ! "$code" =~ ^[0-9]{3}$ ]]; then
    echo "Unable to reach Telegram API for token validation (no HTTP response)." >&2
    return 1
  fi

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    local reason_http=""
    reason_http="$(echo "$resp" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -n "$reason_http" ]]; then
      echo "Telegram token validation failed (HTTP ${code}): ${reason_http}" >&2
    else
      echo "Telegram token validation failed with HTTP ${code}. Raw response: ${resp}" >&2
    fi
    return 1
  fi

  if ! echo "$resp" | grep -q '"ok":[[:space:]]*true'; then
    local reason=""
    reason="$(echo "$resp" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -n "$reason" ]]; then
      echo "Telegram token validation failed: ${reason}" >&2
    else
      echo "Telegram token validation failed. Check TELEGRAM_BOT_TOKEN." >&2
    fi
    return 1
  fi
  return 0
}

random_hex_64() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

ensure_firecrawl_stack() {
  local qwen_key="$1"
  local base_url="$2"
  local model_name="$3"
  local health_timeout="${WHOX_FIRECRAWL_HEALTH_TIMEOUT:-600}"

  echo -e "${CYAN}Provisioning Firecrawl (self-hosted web backend)...${NC}"

  if ! command -v docker >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]] && command -v apt-get >/dev/null 2>&1; then
      echo "Docker not found. Installing docker runtime and compose..."
      apt-get update -y >/dev/null
      if ! apt-get install -y docker.io docker-compose-plugin >/dev/null; then
        echo "docker-compose-plugin unavailable on this image, trying docker-compose package..."
        apt-get install -y docker.io docker-compose >/dev/null
      fi
      systemctl enable --now docker >/dev/null 2>&1 || true
    else
      echo "Docker is required for Firecrawl but was not found and cannot be auto-installed in this context." >&2
      return 1
    fi
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker installation failed (docker command still missing)." >&2
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
    sleep 2
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not running. Unable to start Firecrawl." >&2
    return 1
  fi

  # Prefer Compose v2 plugin (supports modern compose files with top-level `name:`).
  # Some Ubuntu images only provide legacy docker-compose v1 from apt.
  if ! docker compose version >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]] && command -v curl >/dev/null 2>&1; then
      local arch
      arch="$(uname -m)"
      case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) arch="" ;;
      esac
      if [[ -n "$arch" ]]; then
        echo "Installing Docker Compose v2 plugin..."
        mkdir -p /usr/local/lib/docker/cli-plugins
        curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-${arch}" \
          -o /usr/local/lib/docker/cli-plugins/docker-compose || true
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || true
      fi
    fi
  fi

  local -a compose_cmd
  local use_legacy_compose=0
  if docker compose version >/dev/null 2>&1; then
    compose_cmd=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=(docker-compose)
    use_legacy_compose=1
  else
    if [[ "$(id -u)" -eq 0 ]] && command -v apt-get >/dev/null 2>&1; then
      echo "Docker compose command missing. Installing docker-compose..."
      apt-get update -y >/dev/null
      apt-get install -y docker-compose >/dev/null || true
    fi
    if docker compose version >/dev/null 2>&1; then
      compose_cmd=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
      compose_cmd=(docker-compose)
      use_legacy_compose=1
    else
      echo "Docker Compose is required but not available after installation attempts." >&2
      return 1
    fi
  fi

  if [[ ! -d "${FIRECRAWL_DIR}/.git" ]]; then
    echo "Cloning Firecrawl into ${FIRECRAWL_DIR}..."
    mkdir -p "$(dirname "$FIRECRAWL_DIR")"
    git clone --depth=1 "$FIRECRAWL_REPO_URL" "$FIRECRAWL_DIR" >/dev/null
  else
    echo "Updating Firecrawl repo..."
    git -C "$FIRECRAWL_DIR" fetch --depth=1 origin main >/dev/null 2>&1 || true
    git -C "$FIRECRAWL_DIR" reset --hard origin/main >/dev/null 2>&1 || true
  fi

  if [[ -f "${SNAPSHOT_FIRECRAWL_DIR}/searxng/settings.yml" ]]; then
    mkdir -p "${FIRECRAWL_DIR}/searxng"
    cp "${SNAPSHOT_FIRECRAWL_DIR}/searxng/settings.yml" "${FIRECRAWL_DIR}/searxng/settings.yml"
  fi

  local searx_secret
  searx_secret="$(random_hex_64)"

  cat > "${FIRECRAWL_DIR}/.env" <<EOF
PORT=3002
HOST=0.0.0.0
USE_DB_AUTHENTICATION=false
BULL_AUTH_KEY=CHANGEME
SEARXNG_ENDPOINT=http://searxng:8080
SEARXNG_SECRET=${searx_secret}
SEARXNG_CATEGORIES=general,images,videos,news,map
OPENAI_BASE_URL=${base_url}
OPENAI_API_KEY=${qwen_key}
MODEL_NAME=${model_name}
# Optional vars kept explicit to avoid noisy compose warnings on fresh VPS
MODEL_EMBEDDING_NAME=
OLLAMA_BASE_URL=
AUTUMN_SECRET_KEY=
SLACK_WEBHOOK_URL=
TEST_API_KEY=
SUPABASE_ANON_TOKEN=
SUPABASE_URL=
SUPABASE_SERVICE_TOKEN=
SELF_HOSTED_WEBHOOK_URL=
LOGGING_LEVEL=
SEARXNG_ENGINES=
PROXY_SERVER=
PROXY_USERNAME=
PROXY_PASSWORD=
ALLOW_LOCAL_WEBHOOKS=
BLOCK_MEDIA=
EOF

  if [[ ! -f "${FIRECRAWL_DIR}/docker-compose.yaml" ]]; then
    echo "Firecrawl docker-compose.yaml is missing after clone." >&2
    return 1
  fi

  echo "Starting Firecrawl stack..."
  cat > "${FIRECRAWL_DIR}/docker-compose.runtime.yaml" <<'EOF'
services:
  playwright-service:
    image: ghcr.io/firecrawl/playwright-service:latest
    environment:
      PORT: 3000
      MAX_CONCURRENT_PAGES: ${CRAWL_CONCURRENT_REQUESTS:-10}
    networks:
      - backend

  api:
    image: ghcr.io/firecrawl/firecrawl:latest
    environment:
      REDIS_URL: ${REDIS_URL:-redis://redis:6379}
      REDIS_RATE_LIMIT_URL: ${REDIS_URL:-redis://redis:6379}
      PLAYWRIGHT_MICROSERVICE_URL: ${PLAYWRIGHT_MICROSERVICE_URL:-http://playwright-service:3000/scrape}
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
      POSTGRES_HOST: ${POSTGRES_HOST:-nuq-postgres}
      POSTGRES_PORT: ${POSTGRES_PORT:-5432}
      USE_DB_AUTHENTICATION: ${USE_DB_AUTHENTICATION:-false}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      OPENAI_BASE_URL: ${OPENAI_BASE_URL}
      MODEL_NAME: ${MODEL_NAME}
      BULL_AUTH_KEY: ${BULL_AUTH_KEY}
      SEARXNG_ENDPOINT: ${SEARXNG_ENDPOINT}
      SEARXNG_CATEGORIES: ${SEARXNG_CATEGORIES}
      HOST: 0.0.0.0
      PORT: ${INTERNAL_PORT:-3002}
      EXTRACT_WORKER_PORT: ${EXTRACT_WORKER_PORT:-3004}
      WORKER_PORT: ${WORKER_PORT:-3005}
      NUQ_RABBITMQ_URL: amqp://rabbitmq:5672
      ENV: local
    depends_on:
      - redis
      - playwright-service
      - searxng
      - rabbitmq
      - nuq-postgres
    ports:
      - "${PORT:-3002}:${INTERNAL_PORT:-3002}"
    command: node dist/src/harness.js --start-docker
    networks:
      - backend

  searxng:
    image: searxng/searxng:latest
    environment:
      BASE_URL: ${SEARXNG_PUBLIC_BASE_URL:-http://searxng:8080/}
      INSTANCE_NAME: ${SEARXNG_INSTANCE_NAME:-firecrawl-searxng}
      SEARXNG_SECRET: ${SEARXNG_SECRET}
    volumes:
      - ./searxng/settings.yml:/etc/searxng/settings.yml
    networks:
      - backend

  redis:
    image: redis:alpine
    command: redis-server --bind 0.0.0.0
    networks:
      - backend

  rabbitmq:
    image: rabbitmq:3-management
    networks:
      - backend

  nuq-postgres:
    image: ghcr.io/firecrawl/nuq-postgres:latest
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
    networks:
      - backend

networks:
  backend:
    driver: bridge
EOF

  local compose_file="docker-compose.runtime.yaml"
  (
    cd "$FIRECRAWL_DIR"
    local -a compose_run
    compose_run=("${compose_cmd[@]}" --ansi never)
    local -a run_up_cmd
    if [[ "$use_legacy_compose" -eq 1 ]]; then
      echo "Using legacy docker-compose compatibility mode"
      run_up_cmd=("${compose_run[@]}" -f "$compose_file" up -d --no-build)
    else
      run_up_cmd=("${compose_run[@]}" -f "$compose_file" up -d --no-build)
    fi

    echo "Pulling Firecrawl images (this can take a few minutes on first install)..."
    local -a firecrawl_images=(
      "ghcr.io/firecrawl/playwright-service:latest"
      "ghcr.io/firecrawl/firecrawl:latest"
      "ghcr.io/firecrawl/nuq-postgres:latest"
      "searxng/searxng:latest"
      "redis:alpine"
      "rabbitmq:3-management"
    )
    local img
    for img in "${firecrawl_images[@]}"; do
      echo "  pulling ${img}"
      if command -v timeout >/dev/null 2>&1; then
        timeout 900 docker pull "${img}"
      else
        docker pull "${img}"
      fi
    done

    echo "Starting Firecrawl containers..."
    if command -v timeout >/dev/null 2>&1; then
      timeout 600 "${run_up_cmd[@]}"
    else
      "${run_up_cmd[@]}"
    fi
  )

  echo "Waiting for Firecrawl health (timeout: ${health_timeout}s)..."
  local elapsed=0
  local tick=2
  local code_v1 code_root
  while [[ "$elapsed" -lt "$health_timeout" ]]; do
    code_v1="$(firecrawl_http_code "/v1/health")"
    code_root="$(firecrawl_http_code "/")"
    if [[ "$code_v1" == "200" ]]; then
      echo "✓ Firecrawl healthy at http://127.0.0.1:3002"
      return 0
    fi
    # Some Firecrawl builds don't expose /v1/health consistently; if root responds
    # with any normal HTTP status, the API is reachable and ready for WHOX.
    case "$code_root" in
      200|301|302|400|401|403|404|405)
        echo "✓ Firecrawl reachable at http://127.0.0.1:3002 (root HTTP ${code_root})"
        return 0
        ;;
    esac
    if (( elapsed % 10 == 0 )); then
      echo "  still waiting... ${elapsed}s elapsed (health=${code_v1}, root=${code_root})"
    fi
    sleep "$tick"
    elapsed=$((elapsed + tick))
  done

  echo "Firecrawl did not become healthy in time." >&2
  echo "Container status:" >&2
  (
    cd "$FIRECRAWL_DIR"
    "${compose_cmd[@]}" -f "$compose_file" ps >&2 || true
    echo "" >&2
    echo "Last logs (api):" >&2
    "${compose_cmd[@]}" -f "$compose_file" logs --tail=80 api >&2 || true
    echo "" >&2
    echo "Last logs (searxng):" >&2
    "${compose_cmd[@]}" -f "$compose_file" logs --tail=80 searxng >&2 || true
  )
  return 1
}

verify_installation_ready() {
  local whox_bin="$1"
  local scope="$2"

  echo -e "${CYAN}Final verification${NC}"
  if [[ ! -x "$whox_bin" ]]; then
    echo "WHOX binary not found at ${whox_bin}" >&2
    return 1
  fi

  local code_v1 code_root
  code_v1="$(firecrawl_http_code "/v1/health")"
  code_root="$(firecrawl_http_code "/")"
  if [[ "$code_v1" == "200" ]]; then
    echo "✓ Firecrawl API healthy"
  else
    case "$code_root" in
      200|301|302|400|401|403|404|405)
        echo "✓ Firecrawl API reachable (root HTTP ${code_root})"
        ;;
      *)
        echo "Firecrawl health check failed during final verification (health=${code_v1}, root=${code_root})." >&2
        return 1
        ;;
    esac
  fi

  if [[ "$scope" == "system" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      systemctl is-active --quiet whox-gateway || {
        echo "whox-gateway system service is not active." >&2
        return 1
      }
    else
      sudo systemctl is-active --quiet whox-gateway || {
        echo "whox-gateway system service is not active." >&2
        return 1
      }
    fi
    echo "✓ WHOX gateway service active (system)"
  else
    "$whox_bin" gateway status >/dev/null 2>&1 || {
      echo "WHOX gateway user service status check failed." >&2
      return 1
    }
    echo "✓ WHOX gateway service active (user)"
  fi

  if ! "$whox_bin" --help >/dev/null 2>&1; then
    echo "WHOX CLI help check failed." >&2
    return 1
  fi
  echo "✓ WHOX CLI ready"
  return 0
}

ensure_system_gateway_running() {
  local whox_bin="$1"
  local setup_dir="$2"
  local run_as_user="$3"
  local python_exec="${setup_dir}/venv/bin/python"
  local unit_name="whox-gateway.service"
  local unit_file="/etc/systemd/system/${unit_name}"
  local run_home
  run_home="$(getent passwd "${run_as_user}" 2>/dev/null | cut -d: -f6)"
  [[ -z "$run_home" ]] && run_home="/root"

  if [[ ! -x "$python_exec" ]]; then
    echo "System gateway repair failed: Python executable not found at ${python_exec}" >&2
    return 1
  fi

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed "${unit_name}" >/dev/null 2>&1 || true
  systemctl enable "${unit_name}" >/dev/null 2>&1 || true
  systemctl restart "${unit_name}" >/dev/null 2>&1 || true
  sleep 2
  if systemctl is-active --quiet "${unit_name}"; then
    return 0
  fi

  # If systemd reports 203/EXEC or stale paths, overwrite with a known-good unit.
  cat > "${unit_file}" <<EOF
[Unit]
Description=WHOX Agent Gateway - Messaging Platform Integration
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${run_as_user}
WorkingDirectory=${setup_dir}
Environment=HOME=${run_home}
Environment=PYTHONUNBUFFERED=1
ExecStart=${python_exec} -m whox_cli.main gateway run --replace
Restart=always
RestartSec=2
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl reset-failed "${unit_name}" >/dev/null 2>&1 || true
  systemctl enable "${unit_name}" >/dev/null 2>&1 || true
  systemctl restart "${unit_name}" >/dev/null 2>&1 || true
  sleep 2
  if systemctl is-active --quiet "${unit_name}"; then
    return 0
  fi

  echo "System gateway service failed to start after auto-repair." >&2
  systemctl status "${unit_name}" --no-pager -l >&2 || true
  journalctl -u "${unit_name}" -n 80 --no-pager >&2 || true
  return 1
}

apply_snapshot_templates() {
  mkdir -p "$WHOX_HOME"
  if [[ -f "${SNAPSHOT_RUNTIME_DIR}/.env.template" ]]; then
    cp "${SNAPSHOT_RUNTIME_DIR}/.env.template" "${WHOX_HOME}/.env.snapshot.template"
  fi
  if [[ -f "${SNAPSHOT_RUNTIME_DIR}/config.template.yaml" ]]; then
    cp "${SNAPSHOT_RUNTIME_DIR}/config.template.yaml" "${WHOX_HOME}/config.snapshot.template.yaml"
  fi
  if [[ -f "${SNAPSHOT_FIRECRAWL_DIR}/searxng/settings.yml" ]]; then
    mkdir -p "${FIRECRAWL_DIR}/searxng"
    cp "${SNAPSHOT_FIRECRAWL_DIR}/searxng/settings.yml" "${FIRECRAWL_DIR}/searxng/settings.yml"
  fi
}

send_telegram_boot_ping() {
  local token="$1"
  local allowed_csv="$2"
  local chat_id=""
  chat_id="$(echo "$allowed_csv" | cut -d',' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -z "$chat_id" ]]; then
    return 0
  fi
  curl -fsS --max-time 20 \
    -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d "chat_id=${chat_id}" \
    --data-urlencode "text=✅ WHOX is online and ready" >/dev/null 2>&1 || true
}

resolve_setup_dir() {
  # Normal path: running from a cloned repo.
  if [[ -f "${SCRIPT_DIR}/setup-whox.sh" ]]; then
    if [[ -d "${SCRIPT_DIR}/.git" ]]; then
      echo "Updating WHOX repo to latest snapshot..."
      git -C "$SCRIPT_DIR" fetch --depth=1 origin main >/dev/null 2>&1 || true
      git -C "$SCRIPT_DIR" reset --hard origin/main >/dev/null 2>&1 || true
    fi
    SETUP_DIR="$SCRIPT_DIR"
    REPO_ENV_FILE="${SETUP_DIR}/.env"
    return 0
  fi

  # Bootstrap path: running via process substitution (bash <(curl ...)).
  echo -e "${CYAN}Installer bootstrap${NC}"
  echo "Cloning WHOX repo so setup-whox.sh and project files are available"
  mkdir -p "$(dirname "$INSTALL_SRC_DIR")"
  if [[ -d "${INSTALL_SRC_DIR}/.git" ]]; then
    git -C "$INSTALL_SRC_DIR" fetch --depth=1 origin main >/dev/null 2>&1 || true
    git -C "$INSTALL_SRC_DIR" reset --hard origin/main >/dev/null 2>&1 || true
  else
    git clone --depth=1 "$REPO_URL" "$INSTALL_SRC_DIR"
  fi

  if [[ ! -f "${INSTALL_SRC_DIR}/setup-whox.sh" ]]; then
    echo "Failed to locate setup-whox.sh after bootstrap clone at ${INSTALL_SRC_DIR}" >&2
    exit 1
  fi

  SETUP_DIR="$INSTALL_SRC_DIR"
  REPO_ENV_FILE="${SETUP_DIR}/.env"
  echo "✓ Bootstrap complete"
  echo ""
}

banner
echo -e "${CYAN}This install asks for only what WHOX needs${NC}"
echo ""
echo "Get your Qwen API key from:"
echo "https://build.nvidia.com/qwen/qwen3.5-397b-a17b"
echo ""

if [[ -d "$WHOX_HOME" ]]; then
  echo -e "${CYAN}Detected existing WHOX install at ${WHOX_HOME}${NC}"
  echo "Installer will update it in-place to match the current snapshot."
  echo ""
fi

QWEN_KEY="$(prompt_required "1/5 Qwen-3.5-397b-a17b API Key" 0)"
echo "✓ Step 1 complete"
echo ""

TG_BOT_TOKEN="$(prompt_required "2/5 Telegram Bot Token" 0)"
TG_BOT_TOKEN="$(echo "$TG_BOT_TOKEN" | tr -d '[:space:]')"
echo "✓ Step 2 complete"
echo ""

TELEGRAM_ALLOWED_USERS_INPUT="$(read -r -p "3/5 Approved Telegram User IDs (optional, comma-separated): " _tid && echo "${_tid}")"
echo "✓ Step 3 complete"
echo ""

VPS_DOMAIN_INPUT="$(read -r -p "4/5 VPS public base domain (optional, example: whox.ai): " _dom && echo "${_dom}")"
echo "✓ Step 4 complete"
echo ""

TZ_INPUT="$(read -r -p "5/5 Timezone [${DEFAULT_TZ}]: " _tz && echo "${_tz:-$DEFAULT_TZ}")"
echo "✓ Step 5 complete"
echo ""

VPS_DOMAIN_INPUT="$(echo "$VPS_DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]' | sed 's#^https\?://##;s#/$##')"
TELEGRAM_ALLOWED_USERS="$(echo "$TELEGRAM_ALLOWED_USERS_INPUT" | tr -d '[:space:]' | sed 's/^,*//;s/,*$//;s/,,*/,/g')"
TZ_INPUT="$(echo "$TZ_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[[ -z "$VPS_DOMAIN_INPUT" ]] && VPS_DOMAIN_INPUT="$DEFAULT_DOMAIN"
[[ -z "$TZ_INPUT" ]] && TZ_INPUT="$DEFAULT_TZ"

echo -e "${CYAN}Validating Telegram bot token...${NC}"
if validate_telegram_token "$TG_BOT_TOKEN"; then
  echo "✓ Telegram token valid"
else
  echo "Installer cannot continue until Telegram token is valid."
  exit 1
fi
echo ""

echo ""
echo -e "${CYAN}Feature setup${NC}"
echo "Choose what to enable for CLI + Telegram"

ENABLE_WEB=1
ENABLE_BROWSER=1
ENABLE_TERMINAL=1
ENABLE_FILE=1
ENABLE_CODE_EXECUTION=1
ENABLE_VISION=1
ENABLE_IMAGE_GEN=1
ENABLE_MEMORY=1
ENABLE_SESSION_SEARCH=1
ENABLE_SKILLS=1
ENABLE_TODO=1
ENABLE_CRONJOB=1
ENABLE_DELEGATION=1
ENABLE_TTS=1
ENABLE_MOA=0
ENABLE_RL=0

if prompt_yes_no "Use recommended feature profile" "y"; then
  :
else
  if prompt_yes_no "Enable web search and extraction" "y"; then ENABLE_WEB=1; else ENABLE_WEB=0; fi
  if prompt_yes_no "Enable browser automation" "y"; then ENABLE_BROWSER=1; else ENABLE_BROWSER=0; fi
  if prompt_yes_no "Enable terminal commands" "y"; then ENABLE_TERMINAL=1; else ENABLE_TERMINAL=0; fi
  if prompt_yes_no "Enable file operations" "y"; then ENABLE_FILE=1; else ENABLE_FILE=0; fi
  if prompt_yes_no "Enable code execution" "y"; then ENABLE_CODE_EXECUTION=1; else ENABLE_CODE_EXECUTION=0; fi
  if prompt_yes_no "Enable vision/image analysis" "y"; then ENABLE_VISION=1; else ENABLE_VISION=0; fi
  if prompt_yes_no "Enable image generation/editing" "y"; then ENABLE_IMAGE_GEN=1; else ENABLE_IMAGE_GEN=0; fi
  if prompt_yes_no "Enable memory across sessions" "y"; then ENABLE_MEMORY=1; else ENABLE_MEMORY=0; fi
  if prompt_yes_no "Enable session search" "y"; then ENABLE_SESSION_SEARCH=1; else ENABLE_SESSION_SEARCH=0; fi
  if prompt_yes_no "Enable skills management" "y"; then ENABLE_SKILLS=1; else ENABLE_SKILLS=0; fi
  if prompt_yes_no "Enable todo/task planning" "y"; then ENABLE_TODO=1; else ENABLE_TODO=0; fi
  if prompt_yes_no "Enable scheduled cron jobs" "y"; then ENABLE_CRONJOB=1; else ENABLE_CRONJOB=0; fi
  if prompt_yes_no "Enable delegation/sub-agents" "y"; then ENABLE_DELEGATION=1; else ENABLE_DELEGATION=0; fi
  if prompt_yes_no "Enable text-to-speech" "n"; then ENABLE_TTS=1; else ENABLE_TTS=0; fi
  if prompt_yes_no "Enable mixture-of-agents mode" "n"; then ENABLE_MOA=1; else ENABLE_MOA=0; fi
  if prompt_yes_no "Enable RL toolset" "n"; then ENABLE_RL=1; else ENABLE_RL=0; fi
fi

echo ""
install_prerequisites

echo ""
echo -e "${CYAN}Installing WHOX runtime...${NC}"
resolve_setup_dir
WHOX_NONINTERACTIVE=1 "$SETUP_DIR/setup-whox.sh"
apply_snapshot_templates

echo ""
if ! ensure_firecrawl_stack "$QWEN_KEY" "$DEFAULT_BASE_URL" "$DEFAULT_MODEL"; then
  echo "Installer cannot continue because Firecrawl is not healthy." >&2
  exit 1
fi

echo ""
echo -e "${CYAN}Applying WHOX configuration...${NC}"
mkdir -p "$WHOX_HOME"

if [[ -f "${SNAPSHOT_RUNTIME_DIR}/.env.template" ]]; then
  cp "${SNAPSHOT_RUNTIME_DIR}/.env.template" "$ENV_FILE"
fi
if [[ -f "${SNAPSHOT_RUNTIME_DIR}/.env.template" ]]; then
  cp "${SNAPSHOT_RUNTIME_DIR}/.env.template" "$REPO_ENV_FILE"
fi

upsert_env "$ENV_FILE" "TELEGRAM_BOT_TOKEN" "$TG_BOT_TOKEN"
upsert_env "$ENV_FILE" "WHOX_BASE_DOMAIN" "$VPS_DOMAIN_INPUT"
upsert_env "$ENV_FILE" "TZ" "$TZ_INPUT"
if [[ -n "$TELEGRAM_ALLOWED_USERS" ]]; then
  upsert_env "$ENV_FILE" "TELEGRAM_ALLOWED_USERS" "$TELEGRAM_ALLOWED_USERS"
  upsert_env "$ENV_FILE" "GATEWAY_ALLOW_ALL_USERS" "false"
else
  upsert_env "$ENV_FILE" "TELEGRAM_ALLOWED_USERS" ""
  upsert_env "$ENV_FILE" "GATEWAY_ALLOW_ALL_USERS" "true"
fi
upsert_env "$ENV_FILE" "WHOX_QWEN_MAX_RPM" "40"
upsert_env "$ENV_FILE" "WHOX_QWEN_MIN_REQUEST_INTERVAL_SECONDS" "1.7"
upsert_env "$ENV_FILE" "WHOX_QWEN_MAX_INPUT_TOKENS" "90000"
upsert_env "$ENV_FILE" "WHOX_QWEN_RATE_LIMIT_COOLDOWN_SECONDS" "75"
upsert_env "$ENV_FILE" "WHOX_RATE_LIMIT_MAX_RETRIES" "0"
upsert_env "$ENV_FILE" "WHOX_API_MAX_RETRIES" "0"
upsert_env "$ENV_FILE" "WHOX_STREAM_RETRIES" "0"
upsert_env "$ENV_FILE" "WHOX_AGENT_TIMEOUT" "0"
upsert_env "$ENV_FILE" "WHOX_MAX_ITERATIONS" "0"
upsert_env "$ENV_FILE" "FIRECRAWL_API_URL" "http://127.0.0.1:3002"
upsert_env "$ENV_FILE" "TELEGRAM_REPLY_TO_MODE" "off"
upsert_env "$ENV_FILE" "WHOX_HIDE_RATE_LIMIT_STATUS" "1"
upsert_env "$ENV_FILE" "WEBHOOK_ENABLED" "true"
upsert_env "$ENV_FILE" "WHOX_FEATURE_WEB" "$ENABLE_WEB"
upsert_env "$ENV_FILE" "WHOX_FEATURE_BROWSER" "$ENABLE_BROWSER"
upsert_env "$ENV_FILE" "WHOX_FEATURE_TERMINAL" "$ENABLE_TERMINAL"
upsert_env "$ENV_FILE" "WHOX_FEATURE_FILE" "$ENABLE_FILE"
upsert_env "$ENV_FILE" "WHOX_FEATURE_CODE_EXECUTION" "$ENABLE_CODE_EXECUTION"
upsert_env "$ENV_FILE" "WHOX_FEATURE_VISION" "$ENABLE_VISION"
upsert_env "$ENV_FILE" "WHOX_FEATURE_IMAGE_GEN" "$ENABLE_IMAGE_GEN"
upsert_env "$ENV_FILE" "WHOX_FEATURE_MEMORY" "$ENABLE_MEMORY"
upsert_env "$ENV_FILE" "WHOX_FEATURE_SESSION_SEARCH" "$ENABLE_SESSION_SEARCH"
upsert_env "$ENV_FILE" "WHOX_FEATURE_SKILLS" "$ENABLE_SKILLS"
upsert_env "$ENV_FILE" "WHOX_FEATURE_TODO" "$ENABLE_TODO"
upsert_env "$ENV_FILE" "WHOX_FEATURE_CRONJOB" "$ENABLE_CRONJOB"
upsert_env "$ENV_FILE" "WHOX_FEATURE_DELEGATION" "$ENABLE_DELEGATION"
upsert_env "$ENV_FILE" "WHOX_FEATURE_TTS" "$ENABLE_TTS"
upsert_env "$ENV_FILE" "WHOX_FEATURE_MOA" "$ENABLE_MOA"
upsert_env "$ENV_FILE" "WHOX_FEATURE_RL" "$ENABLE_RL"
if [[ -n "$VPS_DOMAIN_INPUT" ]]; then
  upsert_env "$ENV_FILE" "WHOX_ENABLE_APP_WORKSPACES" "1"
else
  upsert_env "$ENV_FILE" "WHOX_ENABLE_APP_WORKSPACES" "0"
fi

# Keep repo-local env aligned for CLI tooling that reads from project root.
upsert_env "$REPO_ENV_FILE" "TELEGRAM_BOT_TOKEN" "$TG_BOT_TOKEN"
upsert_env "$REPO_ENV_FILE" "WHOX_BASE_DOMAIN" "$VPS_DOMAIN_INPUT"
upsert_env "$REPO_ENV_FILE" "TZ" "$TZ_INPUT"
if [[ -n "$TELEGRAM_ALLOWED_USERS" ]]; then
  upsert_env "$REPO_ENV_FILE" "TELEGRAM_ALLOWED_USERS" "$TELEGRAM_ALLOWED_USERS"
  upsert_env "$REPO_ENV_FILE" "GATEWAY_ALLOW_ALL_USERS" "false"
else
  upsert_env "$REPO_ENV_FILE" "TELEGRAM_ALLOWED_USERS" ""
  upsert_env "$REPO_ENV_FILE" "GATEWAY_ALLOW_ALL_USERS" "true"
fi
upsert_env "$REPO_ENV_FILE" "WHOX_QWEN_MAX_RPM" "40"
upsert_env "$REPO_ENV_FILE" "WHOX_QWEN_MIN_REQUEST_INTERVAL_SECONDS" "1.7"
upsert_env "$REPO_ENV_FILE" "WHOX_QWEN_MAX_INPUT_TOKENS" "90000"
upsert_env "$REPO_ENV_FILE" "WHOX_QWEN_RATE_LIMIT_COOLDOWN_SECONDS" "75"
upsert_env "$REPO_ENV_FILE" "WHOX_RATE_LIMIT_MAX_RETRIES" "0"
upsert_env "$REPO_ENV_FILE" "WHOX_API_MAX_RETRIES" "0"
upsert_env "$REPO_ENV_FILE" "WHOX_STREAM_RETRIES" "0"
upsert_env "$REPO_ENV_FILE" "WHOX_AGENT_TIMEOUT" "0"
upsert_env "$REPO_ENV_FILE" "WHOX_MAX_ITERATIONS" "0"
upsert_env "$REPO_ENV_FILE" "FIRECRAWL_API_URL" "http://127.0.0.1:3002"
upsert_env "$REPO_ENV_FILE" "TELEGRAM_REPLY_TO_MODE" "off"
upsert_env "$REPO_ENV_FILE" "WHOX_HIDE_RATE_LIMIT_STATUS" "1"
upsert_env "$REPO_ENV_FILE" "WEBHOOK_ENABLED" "true"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_WEB" "$ENABLE_WEB"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_BROWSER" "$ENABLE_BROWSER"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_TERMINAL" "$ENABLE_TERMINAL"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_FILE" "$ENABLE_FILE"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_CODE_EXECUTION" "$ENABLE_CODE_EXECUTION"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_VISION" "$ENABLE_VISION"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_IMAGE_GEN" "$ENABLE_IMAGE_GEN"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_MEMORY" "$ENABLE_MEMORY"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_SESSION_SEARCH" "$ENABLE_SESSION_SEARCH"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_SKILLS" "$ENABLE_SKILLS"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_TODO" "$ENABLE_TODO"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_CRONJOB" "$ENABLE_CRONJOB"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_DELEGATION" "$ENABLE_DELEGATION"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_TTS" "$ENABLE_TTS"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_MOA" "$ENABLE_MOA"
upsert_env "$REPO_ENV_FILE" "WHOX_FEATURE_RL" "$ENABLE_RL"
if [[ -n "$VPS_DOMAIN_INPUT" ]]; then
  upsert_env "$REPO_ENV_FILE" "WHOX_ENABLE_APP_WORKSPACES" "1"
else
  upsert_env "$REPO_ENV_FILE" "WHOX_ENABLE_APP_WORKSPACES" "0"
fi

WHOX_INSTALL_CONFIG_FILE="$CONFIG_FILE" \
WHOX_INSTALL_MODEL="$DEFAULT_MODEL" \
WHOX_INSTALL_BASE_URL="$DEFAULT_BASE_URL" \
WHOX_INSTALL_QWEN_KEY="$QWEN_KEY" \
WHOX_INSTALL_TZ="$TZ_INPUT" \
WHOX_INSTALL_BASE_DOMAIN="$VPS_DOMAIN_INPUT" \
WHOX_INSTALL_SNAPSHOT_CONFIG_PATH="${SNAPSHOT_RUNTIME_DIR}/config.template.yaml" \
WHOX_ENABLE_WEB="$ENABLE_WEB" \
WHOX_ENABLE_BROWSER="$ENABLE_BROWSER" \
WHOX_ENABLE_TERMINAL="$ENABLE_TERMINAL" \
WHOX_ENABLE_FILE="$ENABLE_FILE" \
WHOX_ENABLE_CODE_EXECUTION="$ENABLE_CODE_EXECUTION" \
WHOX_ENABLE_VISION="$ENABLE_VISION" \
WHOX_ENABLE_IMAGE_GEN="$ENABLE_IMAGE_GEN" \
WHOX_ENABLE_MEMORY="$ENABLE_MEMORY" \
WHOX_ENABLE_SESSION_SEARCH="$ENABLE_SESSION_SEARCH" \
WHOX_ENABLE_SKILLS="$ENABLE_SKILLS" \
WHOX_ENABLE_TODO="$ENABLE_TODO" \
WHOX_ENABLE_CRONJOB="$ENABLE_CRONJOB" \
WHOX_ENABLE_DELEGATION="$ENABLE_DELEGATION" \
WHOX_ENABLE_TTS="$ENABLE_TTS" \
WHOX_ENABLE_MOA="$ENABLE_MOA" \
WHOX_ENABLE_RL="$ENABLE_RL" \
"$SETUP_DIR/venv/bin/python" - <<'PY'
from pathlib import Path
import os
import yaml

cfg_path = Path(os.environ["WHOX_INSTALL_CONFIG_FILE"])
cfg_path.parent.mkdir(parents=True, exist_ok=True)
snapshot_cfg_path = Path(os.environ.get("WHOX_INSTALL_SNAPSHOT_CONFIG_PATH", ""))
if snapshot_cfg_path.exists():
    cfg = yaml.safe_load(snapshot_cfg_path.read_text()) or {}
elif cfg_path.exists():
    cfg = yaml.safe_load(cfg_path.read_text()) or {}
else:
    cfg = {}

model = cfg.setdefault("model", {})
model["default"] = os.environ["WHOX_INSTALL_MODEL"]
model["provider"] = "custom"
model["base_url"] = os.environ["WHOX_INSTALL_BASE_URL"]
model["api_key"] = os.environ["WHOX_INSTALL_QWEN_KEY"]
model["context_length"] = 1_000_000

cfg["timezone"] = os.environ["WHOX_INSTALL_TZ"]

# Clone the behavior profile used in the tuned WHOX install.
agent = cfg.setdefault("agent", {})
agent["max_turns"] = 0
agent["tool_use_enforcement"] = True
agent["verbose"] = False
agent["reasoning_effort"] = "low"
agent["system_prompt"] = (
    "For factual, current-events, people, places, organizations, or verification questions:\\n"
    "- Use web_search first when there is any uncertainty or missing context\\n"
    "- If needed, follow with web_extract on top results before answering\\n"
    "- Do not respond with \\\"I don't know\\\", \\\"I don't have information\\\", or similar without attempting search tools first\\n"
    "- Prefer tool-backed answers over memory-only guesses\\n"
    "- If a first search is ambiguous, run a refined search query immediately\\n"
    "- Keep searching until you can provide a useful answer or a concrete, tool-based failure reason\\n"
    "- For public-information lookups, do not use shell pipelines or execute_code when web_search/web_extract can do the job\\n"
    "- Never pipe downloaded content into interpreters (for example curl|python, wget|bash) for normal Q&A lookups\\n"
    "- If the user references an existing app/site/game (\\\"the app\\\", \\\"current flappy bird game\\\", \\\"the project\\\"), investigate first using session_search and file/browser tools before asking clarifying questions\\n"
    "- For existing project context requests, proactively check likely locations (workspace/apps folders, recent session artifacts, known published URLs) and report findings"
)

terminal = cfg.setdefault("terminal", {})
terminal["timeout"] = 180

web_cfg = cfg.setdefault("web", {})
web_cfg["backend"] = "firecrawl"

display = cfg.setdefault("display", {})
display["compact"] = False
display["resume_display"] = "full"
display["busy_input_mode"] = "interrupt_resume"
display["bell_on_complete"] = False
display["show_reasoning"] = False
display["streaming"] = False
display["inline_diffs"] = True
display["show_cost"] = False
display["skin"] = "default"
display["tool_progress_command"] = False
display["tool_preview_length"] = 0
display["tool_progress"] = "off"
display["background_process_notifications"] = "all"

human_delay = cfg.setdefault("human_delay", {})
human_delay["mode"] = "off"

cron_cfg = cfg.setdefault("cron", {})
cron_cfg["wrap_response"] = False

session_reset = cfg.setdefault("session_reset", {})
session_reset["mode"] = "none"
session_reset["idle_minutes"] = 1440
session_reset["at_hour"] = 4

streaming_cfg = cfg.setdefault("streaming", {})
streaming_cfg["enabled"] = False
streaming_cfg["transport"] = "off"
streaming_cfg["edit_interval"] = 0.08
streaming_cfg["buffer_threshold"] = 8
streaming_cfg["cursor"] = ""

platforms = cfg.setdefault("platforms", {})
telegram_cfg = platforms.setdefault("telegram", {})
telegram_cfg["reply_to_mode"] = "off"

cfg["group_sessions_per_user"] = True

def _on(v: str) -> bool:
    return str(v).strip().lower() in {"1", "true", "yes", "on"}

enabled = []
if _on(os.environ.get("WHOX_ENABLE_BROWSER", "1")):
    enabled.append("browser")
enabled.append("clarify")
if _on(os.environ.get("WHOX_ENABLE_CODE_EXECUTION", "1")):
    enabled.append("code_execution")
if _on(os.environ.get("WHOX_ENABLE_CRONJOB", "1")):
    enabled.append("cronjob")
if _on(os.environ.get("WHOX_ENABLE_DELEGATION", "1")):
    enabled.append("delegation")
if _on(os.environ.get("WHOX_ENABLE_FILE", "1")):
    enabled.append("file")
if _on(os.environ.get("WHOX_ENABLE_IMAGE_GEN", "1")):
    enabled.append("image_gen")
if _on(os.environ.get("WHOX_ENABLE_MEMORY", "1")):
    enabled.append("memory")
if _on(os.environ.get("WHOX_ENABLE_MOA", "0")):
    enabled.append("moa")
if _on(os.environ.get("WHOX_ENABLE_RL", "0")):
    enabled.append("rl")
if _on(os.environ.get("WHOX_ENABLE_SESSION_SEARCH", "1")):
    enabled.append("session_search")
if _on(os.environ.get("WHOX_ENABLE_SKILLS", "1")):
    enabled.append("skills")
if _on(os.environ.get("WHOX_ENABLE_TERMINAL", "1")):
    enabled.append("terminal")
if _on(os.environ.get("WHOX_ENABLE_TODO", "1")):
    enabled.append("todo")
if _on(os.environ.get("WHOX_ENABLE_TTS", "1")):
    enabled.append("tts")
if _on(os.environ.get("WHOX_ENABLE_VISION", "1")):
    enabled.append("vision")
if _on(os.environ.get("WHOX_ENABLE_WEB", "1")):
    enabled.append("web")

enabled = sorted(set(enabled))
cfg.setdefault("platform_toolsets", {})
cfg["platform_toolsets"]["cli"] = list(enabled)
cfg["platform_toolsets"]["telegram"] = list(enabled)

base_domain = (os.environ.get("WHOX_INSTALL_BASE_DOMAIN") or "").strip().lower()
capabilities = ", ".join(enabled) if enabled else "none"
capability_prompt = (
    "\n\nWHOX capability profile for this install:\n"
    f"- Enabled toolsets: {capabilities}\n"
    "- Use enabled tools proactively instead of claiming missing capability\n"
    "- For unknown/current topics, use web tools before responding\n"
    "- When domain is configured, build and publish apps/sites to isolated subdomains under the configured base domain\n"
)
if base_domain:
    capability_prompt += (
        f"- Base publishing domain: {base_domain}\n"
        "- For build/publish requests, choose a clear app slug and publish to <slug>." + base_domain + "\n"
    )
else:
    capability_prompt += (
        "- Base publishing domain: not configured\n"
        "- Build in isolated workspaces locally; do not claim public domain publishing is active until domain is configured\n"
    )

agent["system_prompt"] = (agent.get("system_prompt") or "").rstrip() + capability_prompt

cfg_path.write_text(yaml.safe_dump(cfg, sort_keys=False))
PY

if command -v timedatectl >/dev/null 2>&1; then
  if timedatectl list-timezones | grep -qx "$TZ_INPUT"; then
    if sudo -n true >/dev/null 2>&1; then
      sudo timedatectl set-timezone "$TZ_INPUT" || true
    else
      echo -e "${YELLOW}Note:${NC} system timezone not changed (sudo required). WHOX timezone is still set to ${TZ_INPUT}."
    fi
  else
    echo -e "${YELLOW}Note:${NC} timezone '${TZ_INPUT}' not found in system timezone list. WHOX config still updated."
  fi
fi

WHOX_BIN=""
if [[ -x "$SETUP_DIR/venv/bin/whox" ]]; then
  WHOX_BIN="$SETUP_DIR/venv/bin/whox"
elif command -v whox >/dev/null 2>&1; then
  WHOX_BIN="$(command -v whox)"
fi

if [[ -n "$WHOX_BIN" ]]; then
  echo ""
  echo -e "${CYAN}Configuring WHOX gateway service...${NC}"

  INSTALLED_SCOPE="user"
  RUN_AS_USER="${SUDO_USER:-${USER:-ubuntu}}"
  IS_ROOT=0
  if [[ "$(id -u)" -eq 0 ]]; then
    IS_ROOT=1
  fi

  # Prefer Linux system service for boot-time reliability on VPS.
  if [[ "$(uname -s)" == "Linux" ]] && [[ "$IS_ROOT" -eq 1 ]]; then
    if "$WHOX_BIN" gateway install --system --run-as-user "$RUN_AS_USER" --force; then
      INSTALLED_SCOPE="system"
      if ! ensure_system_gateway_running "$WHOX_BIN" "$SETUP_DIR" "$RUN_AS_USER"; then
        echo -e "${RED}✗${NC} system gateway auto-repair failed."
        exit 1
      fi
    else
      echo -e "${RED}✗${NC} system service install failed."
      exit 1
    fi
  elif [[ "$(uname -s)" == "Linux" ]] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    if sudo "$WHOX_BIN" gateway install --system --run-as-user "$USER" --force; then
      INSTALLED_SCOPE="system"
    else
      echo -e "${YELLOW}Note:${NC} system service install failed, falling back to user service."
      "$WHOX_BIN" gateway install --force || true
      INSTALLED_SCOPE="user"
    fi
  else
    "$WHOX_BIN" gateway install --force || true
    INSTALLED_SCOPE="user"
  fi

  if [[ "$INSTALLED_SCOPE" == "system" ]]; then
    if [[ "$IS_ROOT" -eq 1 ]]; then
      "$WHOX_BIN" gateway restart --system || "$WHOX_BIN" gateway start --system || true
      echo ""
      "$WHOX_BIN" gateway status --system || true
    else
      sudo "$WHOX_BIN" gateway restart --system || sudo "$WHOX_BIN" gateway start --system || true
      echo ""
      sudo "$WHOX_BIN" gateway status --system || true
    fi
    echo "Gateway startup mode: system service (boot enabled)"
  else
    "$WHOX_BIN" gateway restart || "$WHOX_BIN" gateway start || true
    echo ""
    "$WHOX_BIN" gateway status || true
    echo "Gateway startup mode: user service"
  fi

  echo ""
  send_telegram_boot_ping "$TG_BOT_TOKEN" "$TELEGRAM_ALLOWED_USERS"

  if ! verify_installation_ready "$WHOX_BIN" "$INSTALLED_SCOPE"; then
    echo "Installer completed setup steps but final verification failed." >&2
    echo "Run diagnostics:" >&2
    echo "  $WHOX_BIN doctor" >&2
    echo "  $WHOX_BIN gateway status --system" >&2
    exit 1
  fi
else
  echo -e "${YELLOW}Note:${NC} whox command not found on PATH yet. Start manually after shell reload."
fi

echo ""
echo -e "${GREEN}WHOX install complete${NC}"
echo "Model: ${DEFAULT_MODEL}"
echo "Provider endpoint: ${DEFAULT_BASE_URL}"
echo "Timezone: ${TZ_INPUT}"
if [[ -n "$VPS_DOMAIN_INPUT" ]]; then
  echo "Publishing domain: ${VPS_DOMAIN_INPUT}"
  echo "Isolated app/site workspace creation: enabled"
else
  echo "Publishing domain: (not set)"
  echo "Isolated app/site workspace creation: disabled until WHOX_BASE_DOMAIN is set"
fi
if [[ -n "$TELEGRAM_ALLOWED_USERS" ]]; then
  echo "Telegram access: restricted to users ${TELEGRAM_ALLOWED_USERS}"
else
  echo "Telegram access: open (no TELEGRAM_ALLOWED_USERS set)"
fi
echo ""
echo "Start/verify:"
echo "  whox gateway status"
echo "  whox"
