# HolmesGPT: обзор и бенчмарк слабой модели

Дата: 2026-10-03
Репозиторий: `holmesgpt-mem0-qdrant-radar`

Формат: README = статья-обзор и бенчмарк. Спека фиксирует только то, что уже решено. Нерешённое вынесено в конец и в `TODO.md`.

## Цель

Одна статья. Первая часть — обзор: как устроен HolmesGPT, как устроены Radar, VictoriaMetrics, VictoriaLogs, mem0+Qdrant и сценарий расследования. Вторая часть — бенчмарк: насколько каждая добавка меняет долю верных расследований и расход токенов слабой модели.

Список багов нигде не пишется. Скрытой улики нет. Grok 4.7 до тестов пишет код приложений с багами и values с багами. Дешёвая модель код багов не сочиняет.

Симптом даёт человек или скрипт, одной фразой вида «приложение X недоступно». Алерта нет.

Судья расследует сам всеми способами, перечисленными в разделе «Стенд». Слабая модель в этом прогоне видит только MCP этого прогона.

Слабая модель и судья вызываются снаружи, OpenAI-совместимый API. В кластер модели не ставятся.

- Base URL обеих: `https://polza.ai/api/v1`. Ключ только в `terraform.tfvars`, не в репозитории.
- Слабая: `qwen/qwen3.6-27b`. Судья: `x-ai/grok-4.7`. Судья не пишет в память.

## Стенд

Yandex Cloud. Один Yandex Managed Kubernetes, три зоны: `ru-central1-a`, `ru-central1-b`, `ru-central1-d`. Три ноды, по одной на зону. Ноды preemptible, диск HDD, без публичного IP. Исключение — внешний endpoint API master. Egress приватных подсетей — NAT Gateway и route table. VictoriaMetrics — namespace `vmks`.

Нода: 4 vCPU, 16 GB. Kubernetes 1.33. Версию Kubernetes без явного указания не менять.

16 приложений, все с багами: 4 Go, 4 Nuxt, 4 Java, 4 Python. Баги разные. Повторов нет. Имена: `go-1`…`go-4`, `nuxt-1`…`nuxt-4`, `java-1`…`java-4`, `python-1`…`python-4`. Все 16 ставятся из одного Helm-чарта. Код и values с багами пишет Grok 4.7 до тестов. Список багов не ведётся.

Код: `apps/<lang>/<name>/`. Dockerfile один на язык, как в `coroot-kubernetes-observability`: `apps/<lang>/Dockerfile`, context — каталог приложения. Сборка и публикация — GitHub Actions в GHCR, workflow как в том репозитории. Образ: `ghcr.io/patsevanton/holmesgpt-mem0-qdrant-radar/<name>:<semver>`.

Чарт переиспользует шаблоны Deployment и Service: один `deployment.yaml` и один `service.yaml`, `range` по `.Values.apps`. В values — 16 записей, не 16 копий YAML. GitHub MCP читает только этот репозиторий.

Слабая модель не ходит в API кластера. NetworkPolicy закрывает ей доступ к API, логам и метрикам подов. Кластер она видит только через MCP, включённые в текущем прогоне.

Судья ищет причину всеми способами: все MCP сразу, прямой доступ в API Kubernetes, NetworkPolicy на него не распространяется. Ответ слабой модели верный, если названная ею причина совпала с причиной судьи.

Mattermost — только демо. Человек тегает бота как обычного пользователя в канале `#holmes-demo`. Бот забирает сообщение, отдаёт его в HTTP API HolmesGPT и пишет ответ в тред. Готового бота нет, его надо написать. В цифры бенчмарка чат не входит: доля верных и токены считаются только по HTTP API. Для демо — один Go-инцидент. Вход — bot token из `terraform.tfvars`, не из репозитория.

## Прогоны

Каждый прогон — 16 инцидентов. Считаются доля верных ответов, токены и переполнение контекста.

1. Только Radar MCP. VictoriaMetrics не подключена.
2. Radar MCP. VictoriaMetrics подключена через `traffic.prometheusUrl`. Radar сам ходит в неё: `diagnose` получает снимок CPU, памяти и рестартов, доступны `query_prometheus` и `discover_metrics`.
3. Radar MCP и GitHub MCP. VictoriaMetrics не подключена.
4. Radar MCP, VictoriaMetrics через `traffic.prometheusUrl`, GitHub MCP.
5. Radar MCP, VictoriaMetrics через `traffic.prometheusUrl`, VictoriaLogs MCP. GitHub MCP выключен.
6. Radar MCP, VictoriaMetrics, VictoriaLogs MCP, GitHub MCP.

Radar не читает VictoriaLogs. Логи приложений Radar берёт из Kubernetes. VictoriaLogs MCP — отдельный источник, чарт `victoria-logs-mcp`.

Седьмой прогон — mem0+Qdrant. Отложен: исследовать после выбора финалиста из шести. В эту серию не входит. Вопросы в `TODO.md`.

Если все шесть связок переполнили контекст, цифры не публикуются. Вывод инструментов урезается, серия гоняется заново.

## Вне скоупа

- Полный перебор включений MCP.
- Прогон без единого MCP: сравнивать не с чем.
- Прямой доступ слабой модели в Kubernetes. У судьи прямой доступ есть.
- Загрузка кода приложений или всего кода компании в llm-wiki.
- Развёртывание слабой модели и судьи в кластере.
- Использование Mattermost для цифр бенчмарка.

## Зафиксированные версии

- Holmes chart `0.42.0`. Mattermost Team Edition chart `6.6.108`.
- VictoriaMetrics, VictoriaLogs и Radar: перед установкой дешёвая модель берёт latest stable chart и записывает факт в спеку. Не угадывает.

## Не решено

- mem0 и скиллы Grok. Вопросы в `TODO.md`. После выбора финалиста из шести, не в этой серии.
- llm-wiki. Вопросы в `TODO.md`. В эту серию прогонов не входит.
