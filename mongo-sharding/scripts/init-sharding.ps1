# PowerShell: запускать из директории mongo-sharding

# Шаг 1. Инициализация реплика-сетов
docker compose exec -T configSrv mongosh --port 27019 --quiet --eval "rs.initiate({_id: 'configSrvReplSet', configsvr: true, members: [{_id: 0, host: 'configSrv:27019'}]})"
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval "rs.initiate({_id: 'shard1ReplSet', members: [{_id: 0, host: 'shard1:27018'}]})"
docker compose exec -T shard2 mongosh --port 27018 --quiet --eval "rs.initiate({_id: 'shard2ReplSet', members: [{_id: 0, host: 'shard2:27018'}]})"

# Шаг 2. Настройка шардирования через mongos
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('shard1ReplSet/shard1:27018'); sh.addShard('shard2ReplSet/shard2:27018'); sh.enableSharding('somedb'); sh.shardCollection('somedb.helloDoc', {_id: 'hashed'})"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "const d = db.getSiblingDB('somedb'); for (let i = 0; i < 1000; i++) d.helloDoc.insertOne({age: i, name: 'ly' + i})"

Write-Output "Sharding initialized"