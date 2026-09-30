# mongo-sharding-repl

Шардирование + репликация MongoDB: приложение `pymongo-api`, маршрутизатор `mongos`, конфиг-серверы `configSrv-1..3` (реплика-сет) и два шарда `shard1`, `shard2`, каждый из которых — реплика-сет из трёх узлов (1 primary + 2 secondary).

БД — `somedb`, коллекция — `helloDoc`.

Реплика-сеты:

- `configSrvReplSet` — `configSrv-1:27019`, `configSrv-2:27019`, `configSrv-3:27019`
- `shard1ReplSet` — `shard1-1:27018`, `shard1-2:27018`, `shard1-3:27018`
- `shard2ReplSet` — `shard2-1:27018`, `shard2-2:27018`, `shard2-3:27018`

## Запуск кластера

Все команды `docker compose` нужно выполнять из директории проекта `mongo-sharding-repl`:

```shell
cd mongo-sharding-repl
docker compose up -d
```

> Важно: если выполнять команды из родительской директории, `docker compose` найдёт другой `compose.yaml`, в котором нет этих сервисов. Это приведёт к ошибкам вида `service "mongos" is not running` / `no configuration file provided`.

## Инициализация репликации и шардирования

Порядок такой: сначала инициализируем реплика-сеты (config, shard1, shard2), затем добавляем шарды в кластер через `mongos`, включаем шардирование и наполняем данными.

Инициализацию можно выполнить вручную или автоматизировать скриптами:
- Linux/macOS: `scripts/init-replication.sh`
- Windows: `scripts/init-replication.ps1`

> Скрипты **идемпотентны** — их можно запускать повторно в любой момент: уже инициализированные реплика-сеты пропускаются, уже добавленные шарды не дублируются, а данные дозаполняются, только если их нет. Если после перезапуска окружения (или `docker compose down -v`) данные пропали, достаточно выполнить `docker compose up -d` и запустить скрипт ещё раз.

### Linux (bash)

Heredoc `<<EOF` работает только в bash.

#### 1. Инициализируем реплика-сет конфиг-серверов

```bash
docker compose exec -T configSrv-1 mongosh --port 27019 --quiet <<EOF
rs.initiate(
  {
    _id: "configSrvReplSet",
    configsvr: true,
    members: [
      { _id: 0, host: "configSrv-1:27019" },
      { _id: 1, host: "configSrv-2:27019" },
      { _id: 2, host: "configSrv-3:27019" }
    ]
  }
)
EOF
```

#### 2. Инициализируем реплика-сет шарда shard1

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id: "shard1ReplSet",
    members: [
      { _id: 0, host: "shard1-1:27018" },
      { _id: 1, host: "shard1-2:27018" },
      { _id: 2, host: "shard1-3:27018" }
    ]
  }
)
EOF
```

#### 3. Инициализируем реплика-сет шарда shard2

```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id: "shard2ReplSet",
    members: [
      { _id: 0, host: "shard2-1:27018" },
      { _id: 1, host: "shard2-2:27018" },
      { _id: 2, host: "shard2-3:27018" }
    ]
  }
)
EOF
```

После инициализации подождите несколько секунд, пока пройдёт выбор primary и вторые/третьи члены синхронизируются:

```bash
sleep 10
```

> Примечание: `mongos` стартует раньше, чем инициализирован реплика-сет `configSrv`, поэтому он может несколько раз перезапуститься (`restart: on-failure`). Перед работой с `mongos` дождитесь, пока он ответит на ping:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.runCommand({ping: 1})"
```

#### 4. Добавляем шарды в кластер, включаем шардирование и наполняем данными

Через `mongos` добавляем оба реплика-сета как шарды, включаем шардирование БД, шардируем коллекцию и вставляем 1000 документов:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF
```

#### 5. Проверка

Общее количество документов (должно быть `1000`):

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Количество документов в каждом из шардов:

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Сумма по шардам должна равняться общему количеству.

Состояние реплика-сета шарда (кол-во членов, primary/secondary):

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF
```

### Windows (PowerShell)

Heredoc `<<EOF` в PowerShell не работает — используйте `mongosh --eval`. Инициализацию можно автоматизировать скриптом `scripts/init-replication.ps1`.

> Важно: в PowerShell строковые литералы внутри `--eval` оборачивайте в одинарные кавычки, а сам аргумент — в двойные (например, `--eval "db.getSiblingDB('somedb')..."`).

#### 1. Инициализируем реплика-сеты

```powershell
docker compose exec -T configSrv-1 mongosh --port 27019 --quiet --eval "rs.initiate({_id: 'configSrvReplSet', configsvr: true, members: [{_id: 0, host: 'configSrv-1:27019'}, {_id: 1, host: 'configSrv-2:27019'}, {_id: 2, host: 'configSrv-3:27019'}]})"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.initiate({_id: 'shard1ReplSet', members: [{_id: 0, host: 'shard1-1:27018'}, {_id: 1, host: 'shard1-2:27018'}, {_id: 2, host: 'shard1-3:27018'}]})"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "rs.initiate({_id: 'shard2ReplSet', members: [{_id: 0, host: 'shard2-1:27018'}, {_id: 1, host: 'shard2-2:27018'}, {_id: 2, host: 'shard2-3:27018'}]})"
```

После инициализации подождите несколько секунд, пока пройдёт выбор primary и вторые/третьи члены синхронизируются:

```powershell
Start-Sleep -Seconds 10
```

> Примечание: `mongos` стартует раньше, чем инициализирован реплика-сет `configSrv`, поэтому он может несколько раз перезапуститься (`restart: on-failure`). Перед работой с `mongos` дождитесь, пока он ответит на ping:

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.runCommand({ping: 1})"
```

#### 2. Добавляем шарды в кластер, включаем шардирование и наполняем данными

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018'); sh.addShard('shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018'); sh.enableSharding('somedb'); sh.shardCollection('somedb.helloDoc', {_id: 'hashed'})"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "const d = db.getSiblingDB('somedb'); for (let i = 0; i < 1000; i++) d.helloDoc.insertOne({age: i, name: 'ly' + i})"
```

#### 3. Проверка

Общее количество документов (должно быть `1000`):

```powershell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Количество документов в каждом из шардов:

```powershell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Состояние реплика-сета шарда (кол-во членов, primary/secondary):

```powershell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status()"
```

## Проверка через приложение

Приложение: http://localhost:8080

Ответ эндпоинта `/` показывает:

- `collections` — общее количество документов в коллекции `helloDoc` (≥ 1000);
- `shards_documents` — количество документов в каждом из шардов;
- `replicas` — количество членов реплика-сета каждого шарда;
- `mongo_topology_type` — `Sharded`.

> Примечание: если `mongos` стартовал раньше, чем был инициализирован реплика-сет `configSrv`, он может завершиться с ошибкой. В `compose.yaml` у него задан `restart: on-failure`, поэтому он перезапустится сам. Если этого не произошло, выполните `docker compose up -d` ещё раз.