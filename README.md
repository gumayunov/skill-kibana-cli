# kibana-cli

CLI + skill для поиска логов в Elasticsearch через Kibana console proxy.
Инструмент portable и проект-agnostic — его можно использовать с любым стеком
`ES + Kibana + Fluent Bit`, подставив свои host и API-key. Зависит от `bash 4+`,
`curl`, `jq 1.6+`. Для инструкций агенту — см. [`SKILL.md`](SKILL.md).

## One-time setup

### Быстрый путь — через `scripts/setup.sh`

1. Получить admin-пароль Elasticsearch (учётка `elastic` или другая с правом
   создавать API-ключи). Типичный путь — прочитать секрет, куда Helm-чарт
   ES-оператора положил пароль, например:

   ```bash
   export KIBANACLI_ADMIN_PASS=$(
     kubectl get secret -n monitoring <your-es-credentials-secret> \
       -o jsonpath='{.data.password}' | base64 -d
   )
   ```

   Конкретный namespace и имя секрета зависят от того, как развёрнут ваш
   ES-кластер.

2. Запустить интерактивный setup:

   ```bash
   export KIBANACLI_HOST=https://logs.example.com
   ./scripts/setup.sh
   ```

   Скрипт создаст API-key, запишет `~/.config/kibana-cli/env` и прогонит два
   smoke-теста (`--list-indices` и `--since 10m --limit 3`).

   Можно также запустить без env-переменных — скрипт спросит хост и пароль
   интерактивно (пароль — через `read -s`, в history не попадёт).

### Ручной путь

Если нужно полный контроль — команды напрямую.

#### Шаг 1. Admin-пароль

См. выше.

#### Шаг 2. Создать API-key

Kibana 8.x не имеет собственного `/api/security/api_key` endpoint — запросы на
создание/отзыв ключей проходят **через Kibana console proxy** (`/api/console/proxy`).

```bash
curl -sS -u "elastic:$KIBANACLI_ADMIN_PASS" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST 'https://logs.example.com/api/console/proxy?path=_security%2Fapi_key&method=POST' \
  -d '{
    "name": "kibana-cli",
    "role_descriptors": {
      "kibana_cli_reader": {
        "cluster": ["monitor"],
        "index": [{"names": ["logstash-*"], "privileges": ["read", "view_index_metadata", "monitor"]}],
        "applications": [{
          "application": "kibana-.kibana",
          "privileges": ["feature_dev_tools.all"],
          "resources": ["*"]
        }]
      }
    }
  }'
```

Ответ:

```json
{"id":"...","name":"kibana-cli","api_key":"...","encoded":"..."}
```

Нужен **`encoded`** — base64(`id:api_key`), готов к подстановке в заголовок
`Authorization: ApiKey <encoded>`. `id` пригодится, если захочется отозвать ключ
явно по id.

Почему именно такие привилегии:

- `cluster: ["monitor"]` — дефолтно нужно для ряда cat-endpoint'ов.
- `index` `privileges`: `read` + `view_index_metadata` — собственно поиск;
  `monitor` — для `_cat/indices` (без него 403 на `--list-indices`).
- `applications: feature_dev_tools.all` на `kibana-.kibana` — **обязательно**,
  иначе Kibana возвращает 403 на любой запрос через console proxy, несмотря на
  правильные ES-права. API-key получает пересечение прав создателя
  (superuser) и `role_descriptors`, и без Kibana app-privileges пересечение на
  Kibana-слой оказывается пустым.

#### Шаг 3. Env-файл

```bash
mkdir -p ~/.config/kibana-cli
chmod 700 ~/.config/kibana-cli
cat > ~/.config/kibana-cli/env <<'EOF'
KIBANACLI_HOST=https://logs.example.com
KIBANACLI_API_KEY=<encoded>
KIBANACLI_DEFAULT_NAMESPACE=myapp
EOF
chmod 600 ~/.config/kibana-cli/env
```

Путь можно переопределить через `KIBANACLI_ENV=/path/to/env`.

#### Шаг 4. Smoke-тест

```bash
./bin/kibana-cli --list-indices
./bin/kibana-cli --since 10m --limit 3
```

Первая команда должна показать `logstash-YYYY.MM.DD` индекс. Вторая — до трёх
свежих записей.

## Ротация / отзыв API-key

Удобный путь — `scripts/api-key-invalidate.sh`:

```bash
export KIBANACLI_HOST=https://logs.example.com
export KIBANACLI_ADMIN_PASS=...  # см. setup шаг 1
./scripts/api-key-invalidate.sh kibana-cli
```

Отзывает все ключи с именем `kibana-cli` (у одной учётки обычно один актуальный
ключ с этим именем; скрипт убивает все совпадения). После — пересоздать через
`setup.sh`.

Вручную (тот же DELETE через console proxy — **не** Kibana-endpoint
`/api/security/api_key/invalidate`, того не существует):

```bash
curl -sS -u "elastic:$KIBANACLI_ADMIN_PASS" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "https://logs.example.com/api/console/proxy?path=_security%2Fapi_key&method=DELETE" \
  -d '{"name":"kibana-cli"}'
```

## Тесты

```bash
./tests/run.sh
```

Fixture-based, оффлайн — не требует `~/.config/kibana-cli/env` и живого
Elasticsearch. Все тесты должны проходить.

## Зависимости

- **bash ≥ 4** — CLI и test runner проверяют версию явно. На macOS системный
  bash 3.2 не подойдёт: `brew install bash`.
- **curl** — обычно уже есть.
- **jq ≥ 1.6** — `brew install jq` / `apt install jq`.

## Агентская часть

См. [`SKILL.md`](SKILL.md) — триггеры, итеративное сужение поиска,
интерпретация маркеров вроде `[truncated: ... id=...]` и `[hits: N, shown: M]`.

## Что делает CLI (краткий обзор)

- `bin/kibana-cli` — поиск по логам. Флаги: `--since`/`--to` (относительные
  окна) или `--at`/`--until` (абсолютные ISO8601), `--namespace`, `--service`,
  `--level`, `--query` (best-match), `--phrase` (exact match_phrase),
  `--filter <k>=<v>` (term на произвольное поле, повторяемый),
  `--exclude <k>=<v>` (must_not, повторяемый), `--gte <k>=<v>` / `--lte <k>=<v>`
  (range, повторяемые), `--body <file|->` (escape hatch: raw ES query body,
  байпасит все остальные фильтры), `--index`, `--limit`, `--max-len`, `-o`.
  Полный список — `kibana-cli --help`.
- `bin/kibana-cli-get` — достать один документ по `<index>/<id>` (нужно после
  маркера `[truncated: ... id=...]`).
- `presets/*.sh` — обёртки для частых сценариев (`errors-last.sh`, `service.sh`).
- `scripts/setup.sh` — one-shot создание ключа + env-файл + smoke.
- `scripts/api-key-create.sh` — создать ключ, вернуть `encoded` на stdout.
- `scripts/api-key-invalidate.sh <name>` — отозвать все ключи с заданным именем.
