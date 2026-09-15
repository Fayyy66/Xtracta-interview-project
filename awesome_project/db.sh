#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$PROJECT_DIR/.docker.env"

if command -v docker >/dev/null 2>&1; then
  DOCKER_BIN=$(command -v docker)
elif [ -x /Applications/Docker.app/Contents/Resources/bin/docker ]; then
  DOCKER_BIN=/Applications/Docker.app/Contents/Resources/bin/docker
else
  echo "Docker CLI not found. Install and start Docker Desktop." >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE. Copy .docker.env.example to .docker.env first." >&2
  exit 1
fi

exec "$DOCKER_BIN" compose \
  --project-directory "$PROJECT_DIR" \
  --env-file "$ENV_FILE" \
  -f "$PROJECT_DIR/compose.yaml" \
  "$@"
