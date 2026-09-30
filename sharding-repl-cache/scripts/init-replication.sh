#!/bin/bash

set -e

### Ожидание готовности mongod-инстансов
wait_mongo() {
  local svc="$1"
  local port="$2"
  for i in $(seq 1 30); do
    if docker compose exec -T "$svc" mongosh --port "$port" --quiet --eval "db.runCommand({ping: 1})" >/dev/null 2>&1; then
      echo "$svc is ready"
      return 0
    fi
    echo "$svc not ready yet ($i/30)..."
    sleep 2
  done
  echo "ERROR: $svc did not become ready"
  return 1
}

wait_mongo configSrv-1 27019
wait_mongo shard1-1 27018
wait_mongo shard2-1 27018

### Инициализация реплика-сетов (configSrv, shard1, shard2)
### Скрипт идемпотентный: повторный запуск безопасен.
docker compose exec -T configSrv-1 mongosh --port 27019 --quiet <<EOF
function initReplSet(cfg) {
  try {
    rs.status();
    print(cfg._id + ': already initialized');
  } catch (e) {
    rs.initiate(cfg);
    print(cfg._id + ': initialized');
  }
}
initReplSet({
  _id: "configSrvReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv-1:27019" },
    { _id: 1, host: "configSrv-2:27019" },
    { _id: 2, host: "configSrv-3:27019" }
  ]
});
EOF

docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
function initReplSet(cfg) {
  try {
    rs.status();
    print(cfg._id + ': already initialized');
  } catch (e) {
    rs.initiate(cfg);
    print(cfg._id + ': initialized');
  }
}
initReplSet({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
function initReplSet(cfg) {
  try {
    rs.status();
    print(cfg._id + ': already initialized');
  } catch (e) {
    rs.initiate(cfg);
    print(cfg._id + ': initialized');
  }
}
initReplSet({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
});
EOF

### Ждём выбор primary и синхронизацию реплик
sleep 10

### Ожидание готовности mongos (монgos стартует раньше config-реплика-сета и
### может быть перезапущен, поэтому опрашиваем его, пока он не ответит)
echo "Waiting for mongos..."
for i in $(seq 1 30); do
  if docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.runCommand({ping: 1})" >/dev/null 2>&1; then
    echo "mongos is ready"
    break
  fi
  echo "mongos not ready yet ($i/30)..."
  sleep 2
done

### Добавление шардов, включение шардирования и наполнение данными
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
try { sh.addShard("shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018"); } catch(e) { print(e.message); }
try { sh.addShard("shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018"); } catch(e) { print(e.message); }
try { sh.enableSharding("somedb"); } catch(e) { print(e.message); }
try { sh.shardCollection("somedb.helloDoc", { "_id": "hashed" }); } catch(e) { print(e.message); }
var d = db.getSiblingDB("somedb");
if (d.helloDoc.countDocuments({}) === 0) {
  for (var i = 0; i < 1000; i++) d.helloDoc.insertOne({ age: i, name: "ly" + i });
  print("inserted 1000 documents");
} else {
  print("data already present: " + d.helloDoc.countDocuments({}));
}
EOF

echo "Replication initialized"