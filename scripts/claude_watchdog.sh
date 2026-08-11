#!/bin/bash
# Watchdog: si la sesion tmux "claude" (o el proceso claude dentro de ella) muere,
# la vuelve a levantar sin intervencion manual.
while true; do
  if ! tmux has-session -t claude 2>/dev/null; then
    tmux new-session -d -s claude "/home/albertqu/.local/bin/claude --continue"
  fi
  sleep 30
done
