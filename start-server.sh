#!/usr/bin/env bash

DGRAPH_CONTAINER_NAME=dlex-dgraph

if docker ps -a --format '{{.Names}}' | grep -Eq "^${DGRAPH_CONTAINER_NAME}\$"; then
  echo "Already running..."
else
  echo "Starting local dgraph server via Docker..."
  docker run --name $DGRAPH_CONTAINER_NAME -p 8090:8080 -p 9090:9080 -d dgraph/standalone:v2.0.0-rc1
fi
echo "Done."
