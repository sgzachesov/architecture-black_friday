#!/bin/bash

set -e

# Полный сброс: удаляет тома, пересоздаёт кластер и инициализирует его.
docker compose down -v
docker compose up -d
./scripts/init-replication.sh

echo "Cluster reset and initialized"