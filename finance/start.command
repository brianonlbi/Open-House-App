#!/bin/bash
# ---------------------------------------------------------------------------
# Household Finance Tracker — launcher.
#
# Double-click this file (or a desktop alias to it). It serves this folder on
# http://localhost:8777 and opens the app in your default browser.
#
# Why a server at all: a page opened straight off disk (file://) can't reliably
# use IndexedDB or the File System Access API. Served from localhost it can.
# The server binds to 127.0.0.1 only, so nothing on your network can reach it.
# ---------------------------------------------------------------------------
set -u

cd "$(dirname "$0")" || exit 1

PORT=8777
URL="http://localhost:${PORT}/finances.html"

port_open() {
  # /dev/tcp is a bash builtin — no need for nc, which isn't always present.
  (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null && exec 3>&- && return 0
  return 1
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 was not found."
  echo "Install the Xcode command line tools with:  xcode-select --install"
  echo
  read -r -p "Press return to close."
  exit 1
fi

SERVER_PID=""
if port_open; then
  echo "A server is already running on port ${PORT}. Reusing it."
else
  python3 -m http.server "${PORT}" --bind 127.0.0.1 >/dev/null 2>&1 &
  SERVER_PID=$!
  trap 'kill "${SERVER_PID}" 2>/dev/null' EXIT

  # Wait (up to ~4s) for the server to accept connections before opening.
  for _ in $(seq 1 40); do
    port_open && break
    sleep 0.1
  done

  if ! port_open; then
    echo "The server did not start on port ${PORT}."
    echo "Something else may be holding the port."
    read -r -p "Press return to close."
    exit 1
  fi
fi

open "${URL}"

if [ -n "${SERVER_PID}" ]; then
  echo
  echo "  Household Finances is running."
  echo "  Serving: $(pwd)"
  echo "  URL:     ${URL}"
  echo
  echo "  Leave this window open while you use the app."
  echo "  Close it (or press Control-C) to stop the server."
  echo
  wait "${SERVER_PID}"
fi
