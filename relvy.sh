#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Colors & symbols ---
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

CHECK="${GREEN}✔${NC}"
CROSS="${RED}✘${NC}"
WARN="${YELLOW}!${NC}"
ARROW="${CYAN}→${NC}"

APP_NAME="Relvy"
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi
HEALTH_TIMEOUT=120
SERVICES_CORE=(db redis celery-worker web proxy)
SERVICES_RESTARTABLE=(celery-worker web proxy)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo -e "  ${CHECK} $*"; }
warn()  { echo -e "  ${WARN} $*"; }
err()   { echo -e "  ${CROSS} $*"; }
step()  { echo -e "\n${ARROW} ${BOLD}$*${NC}"; }
banner() {
    echo -e "${CYAN}"
    echo -e "  ┌─────────────────────────────┐"
    echo -e "  │         ${BOLD}Relvy CLI${NC}${CYAN}           │"
    echo -e "  └─────────────────────────────┘"
    echo -e "${NC}"
}

get_app_port() {
    local port
    port=$(sed -n '/^  proxy:/,/^  [a-z]/p' docker-compose.yml | grep -oE "'[0-9]+:8080'" | head -1 | cut -d: -f1 | tr -d "'")
    echo "${port:-5001}"
}

get_app_url() {
    echo "http://localhost:$(get_app_port)"
}

open_browser() {
    local url="$1"
    case "$(uname -s)" in
        Darwin)  open "$url" 2>/dev/null ;;
        Linux)   xdg-open "$url" 2>/dev/null ;;
        MINGW*|MSYS*|CYGWIN*) start "$url" 2>/dev/null ;;
    esac
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

check_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker is not installed. Please install Docker first."
        exit 1
    fi
    if ! docker info &>/dev/null; then
        err "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    info "Docker is running"
}


# ---------------------------------------------------------------------------
# Health / Status
# ---------------------------------------------------------------------------

wait_for_healthy() {
    step "Waiting for services to be healthy..."
    local elapsed=0
    local all_healthy
    while [[ $elapsed -lt $HEALTH_TIMEOUT ]]; do
        all_healthy=true
        for svc in "${SERVICES_CORE[@]}"; do
            local state running
            state=$($COMPOSE_CMD ps --format json "$svc" 2>/dev/null | grep -oE '"Health":"[^"]*"' | head -1 | cut -d'"' -f4)
            running=$($COMPOSE_CMD ps --format json "$svc" 2>/dev/null | grep -oE '"State":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [[ "$state" == "healthy" || ( -z "$state" && "$running" == "running" ) ]]; then
                continue
            fi
            all_healthy=false
            break
        done
        if $all_healthy; then
            print_service_health
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        printf "\r  ${DIM}Waiting... %ds / %ds${NC}  " "$elapsed" "$HEALTH_TIMEOUT"
    done
    echo ""
    err "Timed out after ${HEALTH_TIMEOUT}s. Some services may not be healthy."
    print_service_health
    return 1
}

print_service_health() {
    for svc in "${SERVICES_CORE[@]}"; do
        local state
        state=$($COMPOSE_CMD ps --format json "$svc" 2>/dev/null | grep -oE '"Health":"[^"]*"' | head -1 | cut -d'"' -f4)
        local status_label running
        running=$($COMPOSE_CMD ps --format json "$svc" 2>/dev/null | grep -oE '"State":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [[ "$state" == "healthy" || ( -z "$state" && "$running" == "running" ) ]]; then
            status_label="${GREEN}healthy${NC}"
        elif [[ "$running" == "running" ]]; then
            status_label="${YELLOW}starting${NC}"
        else
            status_label="${RED}${running:-unknown}${NC}"
        fi
        printf "  %-20s %b\n" "$svc" "$status_label"
    done
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_start() {
    local no_open=false
    for arg in "$@"; do
        [[ "$arg" == "--no-open" ]] && no_open=true
    done

    banner
    step "Pre-flight checks"
    check_docker

    step "Pulling latest images..."
    $COMPOSE_CMD pull --quiet

    step "Starting services..."
    $COMPOSE_CMD up -d

    if wait_for_healthy; then
        local url
        url="$(get_app_url)"
        echo ""
        info "${BOLD}${APP_NAME} is ready at ${CYAN}${url}${NC}"
        if ! $no_open; then
            info "Opening browser..."
            open_browser "$url"
        fi
    fi
}

cmd_stop() {
    banner
    step "Stopping services..."
    $COMPOSE_CMD down
    info "All services stopped"
}

cmd_restart() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        local allowed=false
        for s in "${SERVICES_RESTARTABLE[@]}"; do
            [[ "$s" == "$service" ]] && allowed=true
        done
        if ! $allowed; then
            err "Cannot restart ${BOLD}${service}${NC} independently."
            echo -e "  Restartable services: ${CYAN}${SERVICES_RESTARTABLE[*]}${NC}"
            exit 1
        fi
        banner
        step "Pre-flight checks"
        check_docker
        step "Restarting ${service}..."
        $COMPOSE_CMD restart "$service"
        info "${service} restarted"
    else
        banner
        step "Pre-flight checks"
        check_docker
        step "Stopping services..."
        $COMPOSE_CMD down
        info "All services stopped"

        step "Pulling latest images..."
        $COMPOSE_CMD pull --quiet

        step "Starting services..."
        $COMPOSE_CMD up -d

        if wait_for_healthy; then
            local url
            url="$(get_app_url)"
            echo ""
            info "${BOLD}${APP_NAME} is ready at ${CYAN}${url}${NC}"
        fi
    fi
}

cmd_status() {
    banner
    step "Service status"

    local running_count=0
    local total=${#SERVICES_CORE[@]}

    for svc in "${SERVICES_CORE[@]}"; do
        local state running
        state=$($COMPOSE_CMD ps --format json "$svc" 2>/dev/null | grep -oE '"Health":"[^"]*"' | head -1 | cut -d'"' -f4)
        running=$($COMPOSE_CMD ps --format json "$svc" 2>/dev/null | grep -oE '"State":"[^"]*"' | head -1 | cut -d'"' -f4)

        local icon status_text
        if [[ "$state" == "healthy" || ( -z "$state" && "$running" == "running" ) ]]; then
            icon="$CHECK"
            status_text="${GREEN}healthy${NC}"
            running_count=$((running_count + 1))
        elif [[ "$running" == "running" ]]; then
            icon="$WARN"
            status_text="${YELLOW}starting${NC}"
        elif [[ -z "$running" ]]; then
            icon="$CROSS"
            status_text="${DIM}not running${NC}"
        else
            icon="$CROSS"
            status_text="${RED}${running}${NC}"
        fi
        printf "  %b %-20s %b\n" "$icon" "$svc" "$status_text"
    done

    local url
    url="$(get_app_url)"
    echo ""
    if [[ $running_count -eq $total ]]; then
        if curl -sf "${url}/health" >/dev/null 2>&1; then
            info "All services healthy — ${url}"
        else
            warn "All services running but app not reachable at $url"
        fi
    elif [[ $running_count -gt 0 ]]; then
        warn "${running_count}/${total} services healthy"
    else
        err "No services running"
    fi
}

cmd_logs() {
    $COMPOSE_CMD logs -f "$@"
}

cmd_destroy() {
    banner
    echo -e "  ${RED}${BOLD}WARNING:${NC} This will destroy all containers, networks, and volumes."
    echo -e "  ${RED}All data in the database will be permanently lost.${NC}"
    echo ""
    read -rp "  Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        warn "Aborted."
        exit 0
    fi

    step "Tearing down everything..."
    $COMPOSE_CMD down -v --remove-orphans
    info "All containers, networks, and volumes removed"
}

cmd_reset() {
    cmd_destroy

    echo ""
    step "Starting fresh..."

    step "Pulling latest images..."
    $COMPOSE_CMD pull --quiet

    step "Starting services..."
    $COMPOSE_CMD up -d

    if wait_for_healthy; then
        local url
        url="$(get_app_url)"
        echo ""
        info "${BOLD}${APP_NAME} is ready at ${CYAN}${url}${NC}"
    fi
}

cmd_help() {
    banner
    echo -e "  ${BOLD}Usage:${NC} ./relvy.sh <command> [options]"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    ${CYAN}start${NC}   [--no-open]   Pull images, start services, open browser"
    echo -e "    ${CYAN}stop${NC}                   Stop all services"
    echo -e "    ${CYAN}restart${NC} [service]      Restart all services, or a specific one"
    echo -e "    ${CYAN}status${NC}                 Show status of all services"
    echo -e "    ${CYAN}logs${NC}    [service] [opts] Tail logs (all or specific service)"
    echo -e "    ${CYAN}destroy${NC}                Tear down everything including data"
    echo -e "    ${CYAN}reset${NC}                  Full teardown (including data) and fresh start"
    echo -e "    ${CYAN}help${NC}                   Show this help message"
    echo ""
    echo -e "  ${BOLD}Examples:${NC}"
    echo -e "    ${DIM}./relvy.sh start${NC}              Start and open browser"
    echo -e "    ${DIM}./relvy.sh start --no-open${NC}    Start without opening browser"
    echo -e "    ${DIM}./relvy.sh logs web${NC}              Follow logs for the web service"
    echo -e "    ${DIM}./relvy.sh logs web --tail 50${NC}    Last 50 lines from web service"
    echo -e "    ${DIM}./relvy.sh restart web${NC}         Restart only the web service"
    echo -e "    ${DIM}./relvy.sh status${NC}             Quick health overview"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        start)   cmd_start "$@" ;;
        stop)    cmd_stop ;;
        restart) cmd_restart "$@" ;;
        status)  cmd_status ;;
        logs)    cmd_logs "$@" ;;
        destroy) cmd_destroy ;;
        reset)   cmd_reset ;;
        help|--help|-h) cmd_help ;;
        *)
            err "Unknown command: ${BOLD}$command${NC}"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
