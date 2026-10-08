#!/usr/bin/env bash
# Run the OnAir server (admin + pages) in the background.
#
#   ./onair.sh            interactive menu
#   ./onair.sh start      start in the background (PID and log in .onair/)
#   ./onair.sh stop       stop it
#   ./onair.sh restart    stop, then start
#   ./onair.sh status     is it running, and where
#   ./onair.sh logs       follow the server output (Ctrl-C to leave)
#   ./onair.sh run        run in the foreground instead
#   ./onair.sh setup      check prerequisites and install what's missing (Node.js 18+, lsof)
#
# Settings are passed through to the server, e.g. PORT=8080, HOST=127.0.0.1, AGENDA_FILE=events/day2.json.
# If the port is taken by another program, you're asked whether to stop it (ONAIR_KILL=1 answers yes without asking).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$ROOT/.onair"
PID_FILE="$STATE/server.pid"
LOG_FILE="$STATE/server.log"
PORT="${PORT:-4242}"
export PORT

# Colours only on a terminal.
if [[ -t 1 ]]; then
  ACC=$'\e[38;5;79m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; OK=$'\e[32m'; BAD=$'\e[31m'; WARN=$'\e[33m'; RST=$'\e[0m'
else
  ACC=""; DIM=""; BOLD=""; OK=""; BAD=""; WARN=""; RST=""
fi

die() { echo "${BAD}onair:${RST} $*" >&2; exit 1; }
interactive() { [[ -t 0 && -t 1 ]]; }
ask() {   # ask "question" default(y|n) → 0 for yes
  local def="$2" a hint; [[ "$def" == y ]] && hint="[Y/n]" || hint="[y/N]"
  read -r -p "$1 $hint " a || return 1
  [[ -z "$a" ]] && a="$def"
  [[ "$a" =~ ^[Yy] ]]
}

# ---------- prerequisites ----------
# OnAir has no libraries to install: the server only uses Node.js built-ins and the pages are plain files.
# It needs Node.js 18 or newer, plus lsof/ps/nohup for this script (standard on macOS and most Linux systems).
NODE_MIN=18

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local major; major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [[ "$major" -ge "$NODE_MIN" ]]
}

pkg_install() {   # pkg_install <homebrew name> <apt/dnf/yum/zypper name> <pacman name>
  local cmd
  if [[ "$(uname -s)" == Darwin ]]; then
    command -v brew >/dev/null || die "Homebrew is needed to install $1 automatically: https://brew.sh (or install $1 yourself)."
    cmd="brew install $1"
  elif command -v apt-get >/dev/null; then cmd="sudo apt-get update && sudo apt-get install -y $2"
  elif command -v dnf >/dev/null;     then cmd="sudo dnf install -y $2"
  elif command -v yum >/dev/null;     then cmd="sudo yum install -y $2"
  elif command -v pacman >/dev/null;  then cmd="sudo pacman -S --noconfirm $3"
  elif command -v zypper >/dev/null;  then cmd="sudo zypper install -y $2"
  else die "no supported package manager found; please install $1 yourself."
  fi
  if [[ -n "${ONAIR_YES:-}" ]]; then :
  elif interactive; then ask "Install $1 with: $cmd ?" y || die "$1 is required; not installed."
  else die "$1 is required. Run: $cmd   (or set ONAIR_YES=1 to let this script install it)"
  fi
  echo "+ $cmd"; eval "$cmd"
}

setup() {
  local missing=0
  if node_ok; then
    echo "${OK}✓${RST} Node.js $(node --version)"
  else
    missing=1
    if command -v node >/dev/null; then echo "${BAD}✗${RST} Node.js $(node --version) is too old (need $NODE_MIN or newer)"; else echo "${BAD}✗${RST} Node.js is not installed"; fi
    # Debian/Ubuntu's default "nodejs" package can be older than 18; NodeSource or nvm give current versions.
    pkg_install node nodejs nodejs
    hash -r
    node_ok || die "Node.js $NODE_MIN+ is still not available. Install a current version from https://nodejs.org (or with nvm) and re-run."
    echo "${OK}✓${RST} Node.js $(node --version)"
  fi
  if command -v lsof >/dev/null; then echo "${OK}✓${RST} lsof"; else missing=1; echo "${BAD}✗${RST} lsof is not installed"; pkg_install lsof lsof lsof; echo "${OK}✓${RST} lsof"; fi
  for tool in ps nohup; do command -v "$tool" >/dev/null || die "'$tool' is missing; it's part of the base system (procps/coreutils), please install it."; done
  echo "${OK}✓${RST} ps, nohup"
  [[ $missing -eq 0 ]] && echo "All prerequisites are in place. There are no other libraries to install."
  return 0
}

ensure_prereqs() { node_ok && command -v lsof >/dev/null && return 0; echo "Checking prerequisites…"; setup; }

# ---------- processes ----------
running_pid() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid cmd; pid="$(cat "$PID_FILE")"
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"   # captured, not piped: grep -q + pipefail is flaky
  if [[ -n "$pid" && "$cmd" == *admin/server.mjs* ]]; then
    echo "$pid"
  else
    rm -f "$PID_FILE"   # stale
    return 1
  fi
}

port_owner() { local p; p="$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null || true)"; echo "${p%%$'\n'*}"; }
describe_pid() {   # "python3.14 -m http.server 4343" rather than the full executable path
  local args first; args="$(ps -p "$1" -o args= 2>/dev/null || true)"
  first="${args%% *}"; args="${first##*/}${args#"$first"}"
  echo "${args:0:70}"
}

terminate() {   # terminate <pid>: TERM, wait up to 3 s, then KILL
  kill "$1" 2>/dev/null || return 0
  for _ in {1..30}; do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done
  kill -9 "$1" 2>/dev/null || true
}

# Offer to stop whatever else is listening on the port. Returns 0 if the port is free afterwards.
free_port() {
  local owner; owner="$(port_owner "$PORT")"
  [[ -z "$owner" ]] && return 0
  echo "${WARN}Port $PORT is in use${RST} by PID $owner: $(describe_pid "$owner")"
  if [[ -n "${ONAIR_KILL:-}" ]]; then :
  elif interactive; then ask "Stop that process?" n || { echo "Left it running. Use another port, e.g. PORT=8080 $0 start."; return 1; }
  else echo "Not stopping it without confirmation (set ONAIR_KILL=1 to allow). Or use PORT=<other>."; return 1
  fi
  terminate "$owner"
  if [[ -n "$(port_owner "$PORT")" ]]; then echo "${BAD}Port $PORT is still in use.${RST}"; return 1; fi
  echo "${OK}Stopped PID $owner.${RST}"
}

# ---------- commands ----------
start() {
  ensure_prereqs
  if pid="$(running_pid)"; then echo "OnAir is already running (PID $pid)."; status; return 0; fi
  free_port || exit 1
  mkdir -p "$STATE"
  # cd first, then background only node itself, so $! is the server's own PID. set -m puts it in its own
  # process group, so Ctrl-C in this terminal (e.g. while following the logs) never reaches the server.
  (set -m; cd "$ROOT"; nohup node admin/server.mjs >"$LOG_FILE" 2>&1 & echo $! >"$PID_FILE")
  for _ in {1..30}; do   # wait up to 3 s for it to listen
    if [[ -n "$(port_owner "$PORT")" ]]; then echo "${OK}OnAir started${RST} (PID $(cat "$PID_FILE"))."; echo; cat "$LOG_FILE"; return 0; fi
    if ! running_pid >/dev/null; then break; fi
    sleep 0.1
  done
  echo "${BAD}OnAir didn't start.${RST} Log:" >&2; cat "$LOG_FILE" >&2; rm -f "$PID_FILE"; exit 1
}

stop() {
  if pid="$(running_pid)"; then
    terminate "$pid"; rm -f "$PID_FILE"
    echo "${OK}OnAir stopped${RST} (PID $pid)."
  elif [[ -n "$(port_owner "$PORT")" ]]; then
    echo "OnAir wasn't started by this script, but something is listening on port $PORT."
    free_port || true
  else
    echo "OnAir is not running."
  fi
}

status() {
  if pid="$(running_pid)"; then
    echo "${OK}●${RST} OnAir is running (PID $pid)."
    [[ -f "$LOG_FILE" ]] && grep -E "^(OnAir admin|Live agenda|Speaker timer|Editing| {14})" "$LOG_FILE" || true
  else
    echo "${DIM}○${RST} OnAir is not running."
    local owner; owner="$(port_owner "$PORT")"
    [[ -n "$owner" ]] && echo "  Port $PORT is used by PID $owner: $(describe_pid "$owner")"
    return 3
  fi
}

logs() {
  [[ -f "$LOG_FILE" ]] || die "no log yet; start the server first."
  tail -n 50 -f "$LOG_FILE"
}

open_url() {
  local url="http://localhost:$PORT$1"
  if command -v open >/dev/null; then open "$url"
  elif command -v xdg-open >/dev/null; then xdg-open "$url" >/dev/null 2>&1 &
  else echo "Open $url in your browser."; return; fi
  echo "Opened $url"
}

# ---------- menu ----------
banner() {
  printf '%s' "$ACC"
  cat <<'ART'
   ___       _   _
  / _ \ _ _ /_\ (_)_ _
 | (_) | ' \/ _ \| | '_|
  \___/|_||_/_/ \_\_|_|
ART
  printf '%s' "$RST"
  echo "  ${DIM}live agenda · presentation · speaker timer${RST}"
}

status_line() {
  local pid owner
  if pid="$(running_pid)"; then
    echo "  ${OK}● running${RST}  PID $pid · port $PORT · ${ACC}http://localhost:$PORT/admin/${RST}"
  elif owner="$(port_owner "$PORT")" && [[ -n "$owner" ]]; then
    echo "  ${WARN}● port $PORT busy${RST}  PID $owner: $(describe_pid "$owner" | cut -c1-48)"
  else
    echo "  ${DIM}○ stopped${RST}  port $PORT"
  fi
}

menu() {
  local key
  while :; do
    clear 2>/dev/null || printf '\n'
    banner; echo; status_line; echo
    printf '  %s1%s Start     %s2%s Stop      %s3%s Restart   %s4%s Status\n' "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
    printf '  %s5%s Logs      %s6%s Admin     %s7%s Agenda    %s8%s Timer\n'  "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
    printf '  %sp%s Port      %ss%s Setup     %sq%s Quit\n'   "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
    echo
    read -rsn1 -p "  Select › " key || exit 0
    echo "$key"; echo
    case "$key" in
      1) ( start ) || true ;;
      2) ( stop ) || true ;;
      3) ( stop; start ) || true ;;
      4) ( status ) || true ;;
      5) echo "${DIM}Following the log. Ctrl-C returns to the menu.${RST}"
         trap ':' INT; ( trap - INT; logs ) || true; trap - INT ;;
      6) open_url "/admin/" ;;
      7) open_url "/" ;;
      8) open_url "/timer.html" ;;
      p|P) local np; read -r -p "  New port (now $PORT): " np || true
           if [[ "$np" =~ ^[0-9]+$ ]] && (( np > 0 && np < 65536 )); then
             if running_pid >/dev/null; then echo "  OnAir is running on $PORT; stop it first, or restart after changing."; fi
             PORT="$np"; export PORT; echo "  Port set to $PORT."
           else echo "  Port unchanged."; fi ;;
      s|S) ( setup ) || true ;;
      q|Q|$'\e') echo "  Bye. (The server keeps running in the background if started.)"; exit 0 ;;
      *) continue ;;
    esac
    echo; read -rsn1 -p "  ${DIM}Press any key for the menu…${RST}" _ || exit 0
  done
}

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  logs)    logs ;;
  run)     ensure_prereqs; free_port || exit 1; cd "$ROOT" && exec node admin/server.mjs ;;
  setup)   setup ;;
  "")      if interactive; then menu; else sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2; fi ;;
  -h|--help|help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)       echo "Unknown command: $1"; sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
