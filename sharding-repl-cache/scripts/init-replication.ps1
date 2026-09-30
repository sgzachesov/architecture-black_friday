# PowerShell: запускать из директории sharding-repl-cache
# Скрипт идемпотентный: повторный запуск безопасен.

function Wait-Mongo([string]$svc, [int]$port) {
  for ($i = 1; $i -le 30; $i++) {
    docker compose exec -T $svc mongosh --port $port --quiet --eval "db.runCommand({ ping: 1 })" *> $null
    if ($LASTEXITCODE -eq 0) {
      Write-Output "$svc is ready"
      return
    }
    Write-Output "$svc not ready yet ($i/30)..."
    Start-Sleep -Seconds 2
  }
  Write-Error "$svc did not become ready"
  exit 1
}

Wait-Mongo configSrv-1 27019
Wait-Mongo shard1-1 27018
Wait-Mongo shard2-1 27018

# Шаг 1. Инициализация реплика-сетов (configSrv, shard1, shard2)
$configInit = @'
function initReplSet(cfg) {
  try { rs.status(); print(cfg._id + ": already initialized"); }
  catch (e) { rs.initiate(cfg); print(cfg._id + ": initialized"); }
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
'@
$configInit | docker compose exec -T configSrv-1 mongosh --port 27019 --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "configSrv init failed"; exit 1 }

$shard1Init = @'
function initReplSet(cfg) {
  try { rs.status(); print(cfg._id + ": already initialized"); }
  catch (e) { rs.initiate(cfg); print(cfg._id + ": initialized"); }
}
initReplSet({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
'@
$shard1Init | docker compose exec -T shard1-1 mongosh --port 27018 --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "shard1 init failed"; exit 1 }

$shard2Init = @'
function initReplSet(cfg) {
  try { rs.status(); print(cfg._id + ": already initialized"); }
  catch (e) { rs.initiate(cfg); print(cfg._id + ": initialized"); }
}
initReplSet({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
});
'@
$shard2Init | docker compose exec -T shard2-1 mongosh --port 27018 --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "shard2 init failed"; exit 1 }

# Ждём выбор primary и синхронизацию реплик
Start-Sleep -Seconds 10

# Ожидание готовности mongos (mongos стартует раньше config-реплика-сета и
# может быть перезапущен, поэтому опрашиваем его, пока он не ответит)
Write-Output "Waiting for mongos..."
$ready = $false
for ($i = 1; $i -le 30; $i++) {
  docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.runCommand({ ping: 1 })" *> $null
  if ($LASTEXITCODE -eq 0) {
    $ready = $true
    Write-Output "mongos is ready"
    break
  }
  Write-Output "mongos not ready yet ($i/30)..."
  Start-Sleep -Seconds 2
}
if (-not $ready) {
  Write-Error "mongos did not become ready"
  exit 1
}

# Шаг 2. Добавление шардов, включение шардирования и наполнение данными
$mongosConfig = @'
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
'@
$mongosConfig | docker compose exec -T mongos mongosh --port 27017 --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "mongos config failed"; exit 1 }

Write-Output "Replication initialized"