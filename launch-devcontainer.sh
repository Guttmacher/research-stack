#!/bin/bash

CONTAINER_NAME="$(basename "$(pwd)")-dev"
IMAGE_NAME="$(basename "$(pwd)")-dev"
REBUILD=false

# Parse arguments
if [[ "$1" == "--rebuild" ]]; then
  REBUILD=true
fi

# Ensure mount directories exist
mkdir -p ~/.container/{aws,vscode-server,amazon-q,codex,cache}

# Stop and remove existing container if running
if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
  read -p "Container $CONTAINER_NAME is running. [c]onnect or [r]estart? (c/r): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Rr]$ ]]; then
    echo "Connecting to existing container..."
    docker exec -it $CONTAINER_NAME /bin/zsh
    exit 0
  fi
  read -p "Type 'restart' and press enter to confirm: " CONFIRM
  if [[ "$CONFIRM" != "restart" ]]; then
    echo "Restart cancelled."
    exit 0
  fi
fi

docker stop $CONTAINER_NAME 2>/dev/null
docker rm $CONTAINER_NAME 2>/dev/null

# Build image if it doesn't exist or rebuild flag is set
if [[ "$REBUILD" == "true" ]] || ! docker image inspect $IMAGE_NAME >/dev/null 2>&1; then
  docker build -t $IMAGE_NAME .devcontainer
fi

# Run persistent container
docker run -d \
  --name $CONTAINER_NAME \
  --hostname "$(basename "$(pwd)")" \
  -w /workspace \
  -v ~/.gitconfig:/home/me/.gitconfig:ro \
  -v ~/.container/aws:/home/me/.aws \
  -v ~/.container/vscode-server:/home/me/.vscode-server \
  -v ~/.container/amazon-q:/home/me/.local/share/amazon-q \
  -v ~/.container/codex:/home/me/.codex \
  -v ~/.container/cache:/home/me/.cache \
  -v "$(pwd)":/workspace \
  -e TZ=$TZ \
  --init \
  $IMAGE_NAME \
  sleep infinity

echo "Container $CONTAINER_NAME started."
docker exec -it $CONTAINER_NAME /bin/zsh
