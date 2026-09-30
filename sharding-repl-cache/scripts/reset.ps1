# PowerShell: запускать из директории sharding-repl-cache
# Полный сброс: удаляет тома, пересоздаёт кластер и инициализирует его.

docker compose down -v
docker compose up -d
& .\scripts\init-replication.ps1

Write-Output "Cluster reset and initialized"