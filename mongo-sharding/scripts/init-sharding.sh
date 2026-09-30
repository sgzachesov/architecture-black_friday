#!/bin/bash

set -e

### Инициализация реплика-сетов
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate(
  {
    _id: "configSrvReplSet",
    configsvr: true,
    members: [ { _id: 0, host: "configSrv:27019" } ]
  }
)
EOF

docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id: "shard1ReplSet",
    members: [ { _id: 0, host: "shard1:27018" } ]
  }
)
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id: "shard2ReplSet",
    members: [ { _id: 0, host: "shard2:27018" } ]
  }
)
EOF

### Настройка шардирования через mongos
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF

echo "Sharding initialized"