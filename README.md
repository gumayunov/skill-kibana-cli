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

#### Per-project конфиг

Если Kibana (или дефолтные фильтры) у каждого проекта своя, env-файл можно
положить в корень проекта — `.kibana-cli/env`. CLI ищет конфиг в таком
порядке: `$KIBANACLI_ENV` → `.kibana-cli/env` вверх по дереву от текущей
директории → `~/.config/kibana-cli/env`. Файл cookie (для SSO-режима) по
умолчанию живёт рядом с env-файлом — у каждого проекта своя cookie.
`.kibana-cli/cookie` в git попадать не должен — добавьте в `.gitignore`
проекта (или положите `.kibana-cli/.gitignore` с строкой `cookie`).

Режим аутентификации задаётся в env-файле параметром `KIBANACLI_AUTH`:
`apikey` (дефолт, нужен `KIBANACLI_API_KEY`) или `cookie` (SSO; см. следующий
раздел).

#### Шаг 4. Smoke-тест

```bash
./bin/kibana-cli --list-indices
./bin/kibana-cli --since 10m --limit 3
```

Первая команда должна показать `logstash-YYYY.MM.DD` индекс. Вторая — до трёх
свежих записей.

## Альтернатива: SSO-cookie (браузерный логин)

Если Kibana спрятана за SSO-прокси (oauth2-proxy / ADFS / SAML) и API-ключ
сделать нельзя (нет admin-доступа, а заголовок `Authorization` до Kibana не
доходит — прокси требует свою cookie), CLI умеет cookie-режим:
`KIBANACLI_AUTH=cookie` в env-файле. Файл cookie CLI берёт рядом с env-файлом
(переопределяется `KIBANACLI_COOKIE_FILE`).

Как это работает:

- `bin/kibana-cli-login` открывает настоящее окно Chromium (Playwright) на
  `KIBANACLI_HOST`; вы проходите SSO как обычно. Как только `GET /api/status`
  с cookie из браузера возвращает 200, cookie сохраняется рядом с env-файлом
  (chmod 600) и окно закрывается.
- Профиль браузера персистентный (`~/.config/kibana-cli/browser-profile`,
  общий на все проекты), поэтому повторный `kibana-cli-login` обычно проходит
  молча — окно мелькает и закрывается без вопросов. Протухла cookie (CLI
  скажет `cookie expired or invalid`) — просто перезапустите login.
- Поиск в этом режиме идёт не через console proxy, а через внутренний API
  Kibana `/internal/search/ese` (тот же, которым пользуется Discover): у
  SSO-пользователей обычно нет Kibana-привилегии `console`, а для этого
  endpoint достаточно прав уровня Discover. `--list-indices` показывает
  data views (`/api/data_views`) вместо `_cat/indices` — по той же причине.

Setup (пример с per-project конфигом):

```bash
npm install && npx playwright install chromium   # one-time, в корне этого репо

# в корне проекта, логи которого смотрим:
mkdir -p .kibana-cli
cat > .kibana-cli/env <<'EOF'
KIBANACLI_HOST=https://kibana.example.com
KIBANACLI_AUTH=cookie
EOF
echo 'cookie' > .kibana-cli/.gitignore

kibana-cli-login          # откроется браузер, после SSO появится .kibana-cli/cookie
kibana-cli --list-indices | head
kibana-cli --index 'my-app-*' --since 10m --limit 3
```

Ограничения cookie-режима: живёт столько, сколько SSO-сессия (обычно
часы–сутки), machine-to-machine сценарии без периодического браузерного
логина не получатся; `kibana-cli-get` достаёт документ через `ids`-query
(прямой `GET <index>/_doc/<id>` тоже требует console-привилегию).

## Поля сообщений и контекста

Схема логов у всех разная, поэтому поля настраиваются в env-файле:

- `KIBANACLI_MESSAGE_FIELDS` (дефолт `event,log,message`) — по каким полям
  ищут `--query`/`--phrase` и из какого поля берётся текст строки в
  `short`/`full` выводе (первое непустое из списка).
- `KIBANACLI_CONTEXT_FIELDS` (дефолт пусто) — whitelist полей для хвоста
  `k=v` в short-выводе. Пусто — показываются все не-служебные поля; если
  логи многословные (объекты метаданных в каждой записи), перечислите
  только нужное. Точка в имени адресует вложенные объекты:
  `KIBANACLI_CONTEXT_FIELDS=host,named_tags.queue,named_tags.trace_id`.

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
- **node ≥ 18 + playwright** — только для `kibana-cli-login` (SSO-cookie
  режим); apikey-режиму не нужны.

## Агентская часть

См. [`SKILL.md`](SKILL.md) — триггеры, итеративное сужение поиска,
интерпретация маркеров вроде `[truncated: ... id=...]` и `[hits: N, shown: M]`.

## Что делает CLI (краткий обзор)

- `bin/kibana-cli` — поиск по логам. Флаги: `--since`/`--to` (относительные
  окна) или `--at`/`--until` (абсолютные ISO8601), `--namespace`, `--service`,
  `--level`, `--query` (best-match), `--phrase` (exact match_phrase),
  `--filter <k>=<v>` (term на произвольное поле, повторяемый),
  `--exclude <k>=<v>` (must_not, повторяемый), `--filter-phrase` /
  `--exclude-phrase <k>=<v>` (match_phrase на произвольное поле — когда нужно
  вхождение токена, а не точное совпадение `.keyword`),
  `--gte <k>=<v>` / `--lte <k>=<v>`
  (range, повторяемые), `--body <file|->` (escape hatch: raw ES query body,
  байпасит все остальные фильтры), `--index`, `--limit`, `--max-len`, `-o`.
  Полный список — `kibana-cli --help`.
- `bin/kibana-cli-get` — достать один документ по `<index>/<id>` (нужно после
  маркера `[truncated: ... id=...]`).
- `presets/*.sh` — обёртки для частых сценариев (`errors-last.sh`, `service.sh`);
  `presets/TEMPLATE.sh` — шаблон проектного пресета (кладётся в `.kibana-cli/`
  проекта рядом с его `env`, см. «Пресеты проекта» в `SKILL.md`).
- `bin/kibana-cli-login` — браузерный SSO-логин для `KIBANACLI_AUTH=cookie`.
- `scripts/setup.sh` — one-shot создание ключа + env-файл + smoke.
- `scripts/api-key-create.sh` — создать ключ, вернуть `encoded` на stdout.
- `scripts/api-key-invalidate.sh <name>` — отозвать все ключи с заданным именем.
