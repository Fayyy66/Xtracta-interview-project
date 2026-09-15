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

MYSQL_PWD=$(sed -n 's/^MYSQL_PWD=//p' "$ENV_FILE" | tail -n 1)
if [ -z "$MYSQL_PWD" ]; then
  echo "MYSQL_PWD is not set in $ENV_FILE." >&2
  exit 1
fi

SDM_IMAGE="beim/schema-data-migration:latest"
if [ "$(uname -m)" = "arm64" ]; then
  SDM_IMAGE="awesome-sdm:0.6.4-arm64"
  if ! "$DOCKER_BIN" image inspect "$SDM_IMAGE" >/dev/null 2>&1; then
    "$DOCKER_BIN" build \
      --file "$PROJECT_DIR/Dockerfile.sdm" \
      --tag "$SDM_IMAGE" \
      "$PROJECT_DIR"
  fi
fi

exec "$DOCKER_BIN" run --rm \
  --add-host host.docker.internal:host-gateway \
  --user "$(id -u):$(id -g)" \
  --volume "$PROJECT_DIR:/workspace" \
  --workdir /workspace \
  --env MYSQL_PWD="$MYSQL_PWD" \
  "$SDM_IMAGE" \
  sdm "$@"
