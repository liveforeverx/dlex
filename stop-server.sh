#!/usr/bin/env bash

DGRAPH_CONTAINER_NAME=dlex-dgraph

if docker ps -a --format '{{.Names}}' | grep -Eq "^${DGRAPH_CONTAINER_NAME}\$"; then
  echo "Stopping and removing dgraph server..."
  docker stop $DGRAPH_CONTAINER_NAME && docker rm $DGRAPH_CONTAINER_NAME
else
  echo "Not running!"
fi
echo "Done."
