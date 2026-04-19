---
name: kibana-cli
description: Use when нужно посмотреть логи кластера с развёрнутым ELK+Fluent Bit — «посмотри логи», «что было в X», «почему упал <pod>», диагностика инцидентов, post-mortem после релиза.
---

# Kibana CLI

Тонкая обёртка над Elasticsearch через `api/console/proxy` Kibana: поиск логов по фильтрам (`--since`/`--to` или абсолютные `--at`/`--until`, `--service`, `--level`, `--query`, `--phrase`, `--filter`, `--exclude`, `--gte`, `--lte`) и расшифровка обрезанных записей по id. Для экзотических запросов (агрегации, `exists`, `wildcard`, `search_after`) — escape hatch `--body <file|->` с raw ES DSL. Все команды — локально, ES/Kibana доступны по HTTPS с API-ключом.

## Pre-requisite

Перед первым запуском в `~/.config/kibana-cli/env` должны быть заданы:

- `KIBANACLI_HOST` — e.g. `https://logs.example.com`
- `KIBANACLI_API_KEY` — base64(id:api_key)
- `KIBANACLI_DEFAULT_NAMESPACE` — дефолтный `kubernetes_namespace_name`

Если файла нет или CLI падает с `no config: set KIBANACLI_HOST …` — см. `README.md` рядом с этим файлом (инструкция по созданию API-ключа и заполнению env).

## Команды

| Команда | Назначение |
|---|---|
| `bin/kibana-cli [options]` | поиск логов по фильтрам |
| `bin/kibana-cli --list-indices` | список доступных индексов и их размер |
| `bin/kibana-cli --help` | перечень всех флагов и дефолтов |
| `bin/kibana-cli-get <index>/<id> [-o short\|full\|json]` | достать один документ по id (например, после обрезки) |
| `presets/errors-last.sh <duration> [extra flags]` | ошибки за `<duration>` в дефолтном namespace |
| `presets/service.sh <service> [extra flags]` | логи одного контейнера (`api`, `worker`, `frontend`, `postgresql`, ...) |

Пресеты — это просто `exec kibana-cli ...` с нужным префиксом флагов; любые дополнительные аргументы прокидываются в CLI и могут переопределить дефолты (например, `--since`, `--limit`).

## Итеративное сужение

1. Старт широкий: `bin/kibana-cli --since 1h --level error` (при инциденте подставь актуальное окно — `30m`, `6h`, `1d`). Если инцидент описан точным временем — `--at 2026-04-19T10:30:00Z --until 2026-04-19T11:00:00Z` вместо относительных.
2. Есть гипотеза по сервису → добавь `--service api|worker|frontend|postgresql|...`.
3. Есть текст / id / имя функции / traceback-сигнатура → `--query "..."` (best-match, матчит по полям `event`, `log`, `message`). Если нужна **точная фраза** (имя constraint, уникальная строка ошибки) — `--phrase "..."` (match_phrase, те же поля).
4. Нужно отфильтровать по произвольному полю (например, `path`, `user_id`, `status`) — `--filter <k>=<v>` (term на `<k>.keyword`). **Исключить** — `--exclude <k>=<v>` (must_not). Числовое сравнение — `--gte <k>=<v>` / `--lte <k>=<v>` (например `--gte status=500` для всех 5xx, `--gte duration_ms=1000` для медленных запросов). Все повторяемы. Пример: `--exclude path=/api/health` убирает health-probes.
5. Слишком много хитов — уточняй `--since`, `--level`, `--service`, потом поднимай `--limit` точечно.
6. Слишком мало и непонятно — сними `--level`, смотри `info|warning` вокруг времени инцидента, чтобы поймать контекст.
7. Нужен запрос, который не выражается флагами (`exists`, `wildcard`, сложный `bool`, агрегации, `search_after`) — `--body <file|->` принимает raw ES DSL. Пример: `jq -n '{...}' | kibana-cli --body - -o json`. Этот флаг игнорирует все остальные фильтры — body идёт в ES как есть.

Всегда стартуй с разумного `--limit` (дефолт 50). Поднимай точечно, когда сузил фильтры.

## Интерпретация маркеров вывода

- `… [truncated: N/M chars, id=<idx>/<id>]` — строка обрезана до `--max-len` (дефолт 1000 codepoints). Полный документ: `bin/kibana-cli-get <idx>/<id> -o full`. **Формат маркера — публичный контракт**, на него завязан парсинг для `kibana-cli-get` — не перефразируй в промтах/скриптах.
- `[hits: X, shown: Y — use --limit N to see more]` — вернулись не все записи. Либо подними `--limit X`, либо сузь фильтры (`--since`, `--level`, `--service`, `--query`).
- `[no hits for filters: ...]` — по этим фильтрам ничего нет. Проверь `--since` (окно может быть слишком узким) и `--namespace` (дефолт из env может быть ограничительным — при кросс-namespace разборе передай явно).

Замечание: `--max-len` считает **codepoints**, не байты. Для ASCII-логов это то же самое; для Unicode reserve ~3x (кириллица занимает ~2 байта/codepoint).

## Разбор инцидента — типичный сценарий

При разборе инцидента или post-mortem после релиза первым шагом:

```bash
presets/errors-last.sh 30m
```

Далее сужение по `--service` в зависимости от симптома (например, `--service api`
если отваливается API, `--service worker` если не отрабатывает фоновый пайплайн,
`--service postgresql` либо `--query migration` для проблем с миграциями).

После того как зацепился за конкретную запись — `bin/kibana-cli-get <idx>/<id> -o full` для полного `_source`.

## Анти-паттерны

- Не делай `--limit 10000` «на всякий случай» — получишь выхлоп больше context window и утопишь разбор.
- Не убирай `--namespace` (дефолт из env) без причины — соседние namespace'ы типа `kube-system`, `monitoring`, `cert-manager` шумные и забьют сигнал.
- При обрезке не додумывай, что было в конце. Читай полный документ через `kibana-cli-get <idx>/<id> -o full`.
- Не используй `-o full` для больших результатов поиска — он дорогой (жирный pretty-print на каждый хит). Для массового просмотра — дефолтный `short`, `full` только точечно на конкретный id.
