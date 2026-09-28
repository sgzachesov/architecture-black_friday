# mongo-sharding

Шардирование MongoDB: приложение `pymongo-api`, маршрутизатор `mongos`, конфиг-сервер `configSrv` и два шарда `shard1`, `shard2`.

БД — `somedb`, коллекция — `helloDoc`.

## Запуск кластера

Все команды `docker compose` нужно выполнять из директории проекта `mongo-sharding`:

```shell
cd mongo-sharding
docker compose up -d
```

> Важно: если выполнять команды из родительской директории, `docker compose` найдёт другой `compose.yaml` (исходного приложения), в котором нет сервисов `mongos`, `configSrv`, `shard1`, `shard2`. В этом случае docker compose вернёт ошибку `service "mongos" is not running` / `no configuration file provided`.

> Примечание: если `mongos` стартовал раньше, чем был инициализирован реплика-сет `configSrv`, он может завершиться с ошибкой. В `compose.yaml` у него задан `restart: on-failure`, поэтому он перезапустится сам. Если этого не произошло, выполните `docker compose up -d` ещё раз.

## Linux (bash)

Инициализацию можно автоматизировать скриптом `scripts/init-sharding.sh`.

### Инициализация

MongoDB требует, чтобы конфиг-сервер и шарды работали как реплика-сеты, поэтому сначала инициализируем реплика-сеты, затем настраиваем шардирование через `mongos`.

#### 1. Инициализируем реплика-сеты

Каждый инстанс (`configSrv`, `shard1`, `shard2`) инициализируется отдельно:

```bash
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate(
  {
    _id: "configSrvReplSet",
    configsvr: true,
    members: [ { _id: 0, host: "configSrv:27019" } ]
  }
)
EOF
```

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id: "shard1ReplSet",
    members: [ { _id: 0, host: "shard1:27018" } ]
  }
)
EOF
```

```bash
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id: "shard2ReplSet",
    members: [ { _id: 0, host: "shard2:27018" } ]
  }
)
EOF
```

#### 2. Настраиваем шардирование через mongos

Один блок команд: добавляем шарды в кластер, включаем шардирование БД, шардируем коллекцию и наполняем её данными. Данные вставляем через `mongos`, чтобы они распределились по шардам:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF
```

### Проверка

Количество документов в коллекции должно быть `1000`:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Распределение данных по шардам:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

Список шардов кластера:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

## Windows (PowerShell)

Инициализацию можно автоматизировать скриптом `scripts/init-sharding.ps1`.

### Инициализация

MongoDB требует, чтобы конфиг-сервер и шарды работали как реплика-сеты, поэтому сначала инициализируем реплика-сеты, затем настраиваем шардирование через `mongos`.

#### 1. Инициализируем реплика-сеты

Каждый инстанс (`configSrv`, `shard1`, `shard2`) инициализируется отдельно:

```powershell
docker compose exec -T configSrv mongosh --port 27019 --quiet --eval "rs.initiate({_id: 'configSrvReplSet', configsvr: true, members: [{_id: 0, host: 'configSrv:27019'}]})"
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval "rs.initiate({_id: 'shard1ReplSet', members: [{_id: 0, host: 'shard1:27018'}]})"
docker compose exec -T shard2 mongosh --port 27018 --quiet --eval "rs.initiate({_id: 'shard2ReplSet', members: [{_id: 0, host: 'shard2:27018'}]})"
```

#### 2. Настраиваем шардирование через mongos

Один блок команд: добавляем шарды в кластер, включаем шардирование БД, шардируем коллекцию и наполняем её данными. Данные вставляем через `mongos`, чтобы они распределились по шардам:

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('shard1ReplSet/shard1:27018'); sh.addShard('shard2ReplSet/shard2:27018'); sh.enableSharding('somedb'); sh.shardCollection('somedb.helloDoc', {_id: 'hashed'})"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "const d = db.getSiblingDB('somedb'); for (let i = 0; i < 1000; i++) d.helloDoc.insertOne({age: i, name: 'ly' + i})"
```

### Проверка

Количество документов в коллекции должно быть `1000`:

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Распределение данных по шардам:

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.getSiblingDB('somedb').helloDoc.getShardDistribution()"
```

Список шардов кластера:

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.status()"
```

Проверить состояние кластера можно и через приложение: http://localhost:8080 (показывает тип топологии, шарды, количество документов).