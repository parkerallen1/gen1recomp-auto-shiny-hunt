#!/bin/sh
# Run the mod's tests under whatever Lua is on the machine. The mod itself
# runs on LuaJIT inside LOVE; nothing here uses syntax the two disagree on,
# so any of these interpreters is a valid check.
#
#   ./tests/run.sh
set -e

cd "$(dirname "$0")/.."

for lua in luajit lua5.4 lua5.3 lua5.1 lua; do
  if command -v "$lua" >/dev/null 2>&1; then
    echo "running tests under $lua"
    exec "$lua" tests/auto_shiny_hunt_test.lua
  fi
done

echo "no lua interpreter found (tried luajit, lua5.4, lua5.3, lua5.1, lua)" >&2
exit 1
