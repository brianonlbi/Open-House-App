#!/bin/bash
# ---------------------------------------------------------------------------
# Household Finances — launcher.
#
# Double-click this file (or a desktop alias to it). It serves this folder on
# a local port and opens the app in your default browser.
#
# Why a server at all: a page opened straight off disk (file://) can't reliably
# use IndexedDB or the File System Access API. Served from localhost it can.
# The server binds to 127.0.0.1 only, so nothing on your network can reach it.
# ---------------------------------------------------------------------------
set -u

cd "$(dirname "$0")" || exit 1

LOG="$(mktemp -t household-finances-log 2>/dev/null || echo /tmp/household-finances.log)"
SERVER_PID=""
PORT=""

finish() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  rm -f "$LOG" 2>/dev/null
}
trap finish EXIT

# --- port checks -----------------------------------------------------------
# Two different questions, deliberately kept apart:
#
#   tcp_open   — is ANYTHING accepting connections here? Must be fast, because
#                it runs in a polling loop. A connect test only.
#   serves_app — is what is there actually this app? One HTTP request, once.
#
# Doing the HTTP check inside the polling loop is what made an earlier version
# appear to hang: a port that accepts connections but never replies burns the
# full timeout on every single poll.
tcp_open() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -G 1 127.0.0.1 "$1" >/dev/null 2>&1 && return 0
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1 && return 0
    return 1
  fi
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3>&- && return 0
  return 1
}

serves_app() {
  command -v curl >/dev/null 2>&1 || return 1
  curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$1/finances.html"
}

# --- find something that can serve a folder ---------------------------------
# /usr/bin/python3 on macOS is only a stub until the Xcode command line tools
# are installed: it exists, so `command -v` finds it, but running it does
# nothing except pop a system dialog. Checking that it *runs* is the point.
python_works() {
  local found
  found="$(command -v python3 2>/dev/null)" || return 1
  if [ "$found" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then
    return 1   # the stub — do not run it, it would just open a dialog
  fi
  python3 -c "import http.server" >/dev/null 2>&1
}

ruby_works() {
  command -v ruby >/dev/null 2>&1 && ruby -e "require 'webrick'" >/dev/null 2>&1
}

SERVER=""
if python_works; then
  SERVER="python3"
elif ruby_works; then
  SERVER="ruby"
else
  echo
  echo "  This Mac has no working web server built in yet."
  echo
  echo "  Install Apple's command line tools — it is free, takes a few minutes,"
  echo "  and you only do it once. Copy this line, paste it into Terminal, and"
  echo "  press return:"
  echo
  echo "      xcode-select --install"
  echo
  echo "  A window will appear. Click Install and wait for it to finish, then"
  echo "  double-click start.command again."
  echo
  read -r -p "  Press return to close. "
  exit 1
fi

start_server() {
  case "$SERVER" in
    python3) python3 -m http.server "$1" --bind 127.0.0.1 >"$LOG" 2>&1 & ;;
    ruby)    ruby -run -e httpd . -p "$1" -b 127.0.0.1 >"$LOG" 2>&1 & ;;
  esac
  SERVER_PID=$!
}

# --- take the first usable port, so a stuck one is never a dead end ---------
for candidate in 8777 8778 8779 8780 8781; do
  if tcp_open "$candidate"; then
    if serves_app "$candidate"; then
      # This app is already running from an earlier double-click. Use it.
      PORT="$candidate"
      SERVER_PID=""
      echo "  Already running on port $candidate — opening that."
      break
    fi
    # Something else owns this port. Leave it alone and try the next one.
    continue
  fi

  start_server "$candidate"
  for _ in $(seq 1 40); do
    tcp_open "$candidate" && break
    sleep 0.1
  done

  if tcp_open "$candidate"; then
    PORT="$candidate"
    break
  fi

  kill "$SERVER_PID" 2>/dev/null
  SERVER_PID=""
done

if [ -z "$PORT" ]; then
  echo
  echo "  The server would not start. Here is what it said:"
  echo
  sed 's/^/      /' "$LOG" 2>/dev/null | head -20
  echo
  echo "  Send that to Claude and it will sort it out."
  echo
  read -r -p "  Press return to close. "
  exit 1
fi

URL="http://localhost:${PORT}/finances.html"
if command -v open >/dev/null 2>&1; then
  open "$URL"
else
  echo "  Open this in your browser: ${URL}"
fi

echo
echo "  Household Finances is running."
echo
echo "  Folder: $(pwd)"
echo "  Address: ${URL}"
echo
echo "  Leave this window open while you use the app."
echo "  Close it, or press Control-C, to stop."
echo

if [ -n "$SERVER_PID" ]; then
  wait "$SERVER_PID"
else
  read -r -p "  Press return to close this window. "
fi
