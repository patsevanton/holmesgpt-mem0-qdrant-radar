# HolmesGPT: демонстрация на стенде

Дата: 2026-10-03
Репозиторий: `holmesgpt-mem0-qdrant-radar`

Формат: README = статья-обзор и демонстрация. Спека фиксирует только то, что уже решено. Нерешённое вынесено в конец и в `TODO.md`.

Читатель — разработчик, SRE или DevOps. После статьи он понимает, как устроен HolmesGPT, и поднимает стенд. README объясняет установку Radar и HolmesGPT, переключение вариантов (Radar вкл/выкл, встроенные tools HolmesGPT вкл/выкл) и интерактивное тестирование через Mattermost. Симптом — «приложение недоступно». Terraform, установку VictoriaMetrics и VictoriaLogs README объясняет. Base URL и ключ — в `terraform.tfvars`. `AGENTS.md` говорит взять их оттуда и значения не копирует. В README — только имена моделей.

Тестирует человек интерактивно. Агент исполняет те же команды, что читает читатель.

Mattermost поднимает агент вместе со стендом. В README это отдельный раздел: как зайти в `#holmes-demo` и тегнуть бота, плюс плейсхолдер скриншота. Скриншот добавляет человек перед публикацией.

## Цель

Одна статья. Первая часть — обзор: как устроен HolmesGPT, как устроены Radar, VictoriaMetrics, VictoriaLogs и сценарий расследования. Вторая часть — демонстрация: как добавить Radar и встроенные tools HolmesGPT меняет расследование слабой модели. mem0+Qdrant и llm-wiki в эту статью не входят.

Список багов нигде не пишется. Скрытой улики нет. Grok 4.7 до тестов пишет код приложения с багами и values с багами. Дешёвая модель код багов не сочиняет.

Симптом даёт человек, одной фразой вида «приложение X недоступно». Алерта нет.

Слабая модель вызывается снаружи, OpenAI-совместимый API. В кластер модель не ставится.

- Base URL — OpenAI-совместимый endpoint. Значение ключа и base URL только в `terraform.tfvars`, не в репозитории.
- Слабая: `deepseek/deepseek-v4.1-flash`.

## Стенд

Yandex Cloud. Один Yandex Managed Kubernetes, три зоны: `ru-central1-a`, `ru-central1-b`, `ru-central1-d`. Три ноды, по одной на зону. Ноды preemptible, диск HDD, без публичного IP. Исключение — внешний endpoint API master. Egress приватных подсетей — NAT Gateway и route table. VictoriaMetrics — namespace `vmks`.

Нода: 4 vCPU, 16 GB. Kubernetes 1.33. Версию Kubernetes без явного указания не менять.

Одно приложение `go-1` с багом, ставится из Helm-чарта. Код и values с багом пишет Grok 4.7 до тестов. Список багов не ведётся.

Код: `apps/<lang>/<name>/`. Dockerfile один на язык, как в `coroot-kubernetes-observability`: `apps/<lang>/Dockerfile`, context — каталог приложения. Сборка и публикация — GitHub Actions в GHCR, workflow как в том репозитории. Образ: `ghcr.io/patsevanton/holmesgpt-mem0-qdrant-radar/<name>:<semver>`.

Чарт переиспользует шаблоны Deployment и Service: один `deployment.yaml` и один `service.yaml`, `range` по `.Values.apps`. В values — одна запись, не копия YAML.

Слабая модель не ходит в API кластера. NetworkPolicy закрывает ей доступ к API, логам и метрикам подов. Кластер она видит только через MCP и встроенные tools, включённые в текущем варианте.

Mattermost — интерфейс тестирования. Человек тегает бота как обычного пользователя в канале `#holmes-demo`. Бот забирает сообщение, отдаёт его в HTTP API HolmesGPT и пишет ответ в тред. Готового бота нет, его надо написать. Вход — bot token из `terraform.tfvars`, не из репозитория.

## Варианты

1. Без Radar, без встроенных tools HolmesGPT.
2. Radar MCP, без встроенных tools.
3. Без Radar, встроенные tools HolmesGPT включены (`kubernetes/*`, `prometheus/metrics`, `bash`, `kubectl-run`, `helm/core`).
4. Radar MCP, встроенные tools HolmesGPT включены.

Radar не читает VictoriaLogs. Логи приложения Radar берёт из Kubernetes. VictoriaLogs MCP — отдельный источник, чарт `victoria-logs-mcp`.

## Вне скоупа

- Полный перебор включений MCP.
- Прямой доступ слабой модели в Kubernetes. У человека прямой доступ есть.
- Развёртывание слабой модели в кластере.

## Зафиксированные версии

- Holmes chart `0.42.0`. Mattermost: оператор `mattermost-operator 1.0.5` (operator
  `1.25.4`), образ `mattermost/mattermost-team-edition:11.11.1`, БД — PostgreSQL
  (CloudNativePG).
- VictoriaMetrics, VictoriaLogs и Radar: перед установкой дешёвая модель берёт latest stable chart и записывает факт в спеку. Не угадывает.
- Установлено (latest stable на 2026-10-03):
  - victoria-metrics-k8s-stack `0.95.0` (app `v1.153.0`), namespace `vmks`
  - victoria-logs-single `0.13.10` (app `v1.53.0`), namespace `vmks`
  - radar `1.15.0` (`skyhook/radar`), MCP включён
  - holmes `0.42.0` (`robusta/holmes`)
  - mattermost-operator `1.0.5` (operator `1.25.4`), образ
    `mattermost/mattermost-team-edition:11.11.1`, БД — CloudNativePG (PostgreSQL)
