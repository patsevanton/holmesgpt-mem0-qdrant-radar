# TODO

## llm-wiki

Отложено. В текущую серию прогонов не входит.

Зафиксировано:

- llm-wiki не клонирует и не кэширует GitHub. Источник надо загрузить самим и дождаться индексации.
- Весь код компании в вики не грузим: его слишком много.
- Отдельный тест, не часть шести прогонов Radar/VM/VictoriaLogs/GitHub и не часть прогона mem0.
- В вики загружается один Helm-чарт, не код приложений и не схема взаимодействия.
- Все 16 приложений ставятся из этого чарта.
- Штатного toolset HolmesGPT для llm-wiki нет. Подключение возможно только как внешний MCP.
- `nashsu/llm_wiki` имеет MCP, но это десктоп с локальным HTTP API, не сервис кластера.
- Karpathy-паттерн (`llm-wiki-mcp`) — markdown и инструменты чтения/записи, не индексатор чарта.
- На время расследования запись в вики должна быть закрыта.

Не решено:

- Какую реализацию llm-wiki ставить в кластер.
- Как HolmesGPT читает страницы: свой read-only MCP, GitHub MCP или файлы в поде.
- Какая связка MCP включена во время теста вики.
- Что именно из Helm-чарта загружается и по какому признаку индексация считается законченной.

## Переименование bench → holmsgpt

Переименовать стенд с `bench` на `holmsgpt`:
- K8s-кластер `yandex_kubernetes_cluster.bench` (`name = "bench"`) в `k8s.tf`.
- Node-group `bench-node-group`.
- Service account `bench-sa-k8s-editor`.
- VPC-сеть `bench-vpc`, подсети `bench-a/b/d` (`net.tf`).
- Helm-чарт `bench-apps`, helper-шаблоны `bench-apps.labels` и `bench-apps.image` (`chart/`).
- Terraform-имена ресурсов, output и ссылки на них.

## mem0 и скиллы

Отложено. Исследовать после того, как из шести связок выявлен финалист. В текущую серию не входит.

Зафиксировано:

- Grok 4.7 не участвует в расследовании и не пишет в mem0.
- Grok 4.7 может один раз написать скиллы. Они одинаковые у всех слабых прогонов, без имён багов и фиксов.
- HolmesGPT умеет markdown-скиллы (`fetch_skill`) начиная с 0.26.0.
- Своего toolset HolmesGPT для mem0 нет. Подключение возможно только как внешний MCP.
- Кто пишет в mem0, что именно пишется и когда слабая модель это читает — не решено. До выбора финалиста не проектировать.

## Бот Mattermost для демо

Отложено. Поискать и подумать.

Зафиксировано:

- Готового бота под схему «сообщение в канале `#holmes-demo` → HTTP API HolmesGPT → ответ в тред» нет.
- Официальной интеграции HolmesGPT↔Mattermost нет (HolmesGPT issue #2104 «Feature Request: Add Mattermost Integration» открыт).
- Mattermost Agents plugin (`mattermost-plugin-agents`) подключает LLM-провайдера напрямую, а не вызывает HTTP API HolmesGPT — не подходит под схему спеки.
- Заготовки `mattermost_bot` (Python) и Sample Go bot (Mattermost Go driver) — не мост к HolmesGPT.
- matterbridge, BridgeMost — мосты между чатами, не то.

Не решено:

- Искать дальше готовое решение или писать своего лёгкого бота (Deployment + образ) под HTTP API HolmesGPT.
- Как бот определяет, что сообщение адресовано ему, и куда пишет ответ (тред).
- Bot token: секрет `mattermost-bot-token` уже генерируется Terraform.
