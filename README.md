# holmesgpt-mem0-qdrant-radar

Бенчмарк HolmesGPT на Yandex Managed Kubernetes. Схема и прогоны — в
[docs/superpowers/specs/2026-10-03-holmesgpt-bench-design.md](docs/superpowers/specs/2026-10-03-holmesgpt-bench-design.md).
Правила проекта — в [AGENTS.md](AGENTS.md).

## Требования

- [yc CLI](https://yandex.cloud/ru/docs/cli/), аутентифицированный (`yc init`)
- Terraform >= 1.3, kubectl, Helm >= 3

## Секреты (terraform.tfvars, в git не попадает)

Кластер создаётся Terraform. Base URL, ключ, bot token и GitHub-токен берутся из
`terraform.tfvars` и в репозиторий не копируются:

```hcl
folder_id              = "b1gxxxxxxxxxxxxxxxx"
llm_base_url           = "..."   # OpenAI-совместимый base URL слабой модели и судьи
llm_api_key            = "..."   # ключ LLM, общий для слабой модели и судьи
mattermost_bot_token   = "..."
github_token           = "..."   # read-only GitHub PAT для GitHub MCP (связки 3, 4, 6)
```

Секреты `holmes-llm-credentials`, `mattermost-bot-token` и `github-mcp-token`
генерируются Terraform из `llm_api_key`, `llm_base_url`, `mattermost_bot_token` и
`github_token` в файлы `k8s/holmes-llm-credentials.yaml`,
`k8s/mattermost-bot-token.yaml` и `k8s/github-mcp-token.yaml` (в `.gitignore`, в git
не попадают) и применяются в кластер через `kubectl apply -f`.
`holmes-llm-credentials` применяется перед установкой HolmesGPT (шаг 4),
`mattermost-bot-token` — перед установкой Mattermost (шаг 5).
`github-mcp-token` создаётся только если `github_token` непустой; он нужен для
GitHub MCP (связки 3, 4, 6) и применяется перед HolmesGPT.

### Read-only токен GitHub

Для GitHub MCP нужен **read-only** токен. Два варианта:

- **Classic PAT** (`ghp_…`): scope `repo` (доступ к репозиторию, issues, PR;
  `public_repo` входит неявно). Для организаций — добавить `read:org`.
- **Fine-grained PAT** (`github_pat_…`): Repository access — только этот репозиторий,
  права **Metadata: Read** (обязательно), **Contents: Read**, **Issues: Read**,
  **Pull requests: Read**, **Actions: Read**.

Токен попадает в `terraform.tfvars` (`github_token`), Terraform рендерит его в
`k8s/github-mcp-token.yaml`, а `helm upgrade` Holmes получает
`mcpAddons.github.auth.secretName=github-mcp-token`. Секрет можно создать и вручную:
`kubectl create secret generic github-mcp-token -n holmes --from-literal=token=<PAT>`.

Пароль PostgreSQL для Mattermost в репозитории не хранится: `k8s/mattermost-apply.sh`
читает его из кластерного секрета CloudNativePG (`mm-pg-app`) в момент запуска.

## Инфраструктура

```bash
terraform init
terraform apply -auto-approve
eval "$(terraform output -raw k8s_cluster_credentials_command)"
kubectl get nodes
```

Ноды preemptible, диск HDD, без публичного IP; egress — NAT Gateway и route table.
Публичный вход — балансировщик Traefik на зарезервированном IP
(`terraform output -raw ingress_public_ip`). DNS не нужен: используется sslip.io
(`<сервис>.<IP>.sslip.io`). Версию Kubernetes без явного указания не менять.

## Порядок установки стенда

Строгий порядок: vmks создаёт CRD оператора и vmagent.

### 1. VictoriaMetrics

`victoria-metrics-k8s-stack 0.95.0` в namespace `vmks`. В values отключены scrape-job
и recording-правила control-plane Yandex Managed K8s (`kubeControllerManager`,
`kubeScheduler`, `kubeEtcd`, группы `etcd`, `kubernetes-system-scheduler`,
`kubernetes-system-controller-manager`, `kube-scheduler.rules`): master управляемый и
вне кластера.

```bash
helm upgrade --install vmks oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack \
  --namespace vmks --create-namespace --version 0.95.0 --wait -f values/vmks-values.yaml
```

### 2. VictoriaLogs + коллектор vlagent

`victoria-logs-single 0.13.10` в namespace `vmks`. Коллектор — `victoria-logs-collector`
(образ `vlagent`), логи всех подов уходят в VictoriaLogs.

```bash
helm upgrade --install vlogs oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-single \
  --namespace vmks --create-namespace --version 0.13.10 --wait

helm upgrade --install vlogs-collector oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-collector \
  --namespace vmks --version 0.3.8 --wait \
  --set 'remoteWrite[0].url=http://vlogs-victoria-logs-single-server.vmks.svc:9428'
```

VictoriaLogs MCP (`victoria-logs-mcp 0.2.0`, app `v1.9.0`) — отдельный источник
логов для связок 5 и 6:

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

helm upgrade --install vlogs-mcp vm/victoria-logs-mcp \
  --namespace vmks --version 0.2.0 --wait \
  --set 'vl.entrypoint=http://vlogs-victoria-logs-single-server.vmks.svc:9428'
```

MCP-сервер поднимается на `vlogs-mcp-victoria-logs-mcp.vmks.svc:8080`, endpoint
`/mcp`.

### 3. Radar

`skyhook/radar 1.15.0`, MCP включён. VictoriaMetrics подключается через
`traffic.prometheusUrl` (связки 2, 4, 5, 6). Radar не читает VictoriaLogs — логи
приложений он берёт из Kubernetes.

У Radar есть read-only MCP endpoint `/mcp-readonly` (25 инструментов вместо 32:
убраны `apply_resource`, `patch_resource`, `manage_*`). Слабая модель ходит только
в него, чтобы не менять кластер.

```bash
helm upgrade --install radar oci://ghcr.io/skyhook-io/charts/radar \
  --namespace radar --create-namespace --version 1.15.0 --wait \
  --set 'mcp.enabled=true' \
  --set 'traffic.prometheusUrl=http://vmsingle-vmks-victoria-metrics-k8s-stack.vmks.svc:8428'
```

`traffic.prometheusUrl` задаётся для связок 2, 4, 5, 6; для связок 1 и 3 он пуст.

### 4. HolmesGPT

`robusta/holmes 0.42.0`. MCP текущего прогона, модель из `terraform.tfvars`. Ключ и
base URL монтируются в под через Secret.

По спеке слабая модель не ходит в API Kubernetes, логи и метрики подов напрямую —
кластер она видит только через MCP. Поэтому в `values/holmes-values.yaml`:

- отключены прямые toolsets `kubernetes/core`, `kubernetes/logs`,
  `kubernetes/live-metrics`, `kubernetes/kube-prometheus-stack`,
  `kubernetes/krew-extras`, `kubernetes/kube-lineage-extras`, `prometheus/metrics`,
  `bash`, `kubectl-run`, `helm/core`;
- включён Radar MCP (`mcp_servers.radar`) для всех прогонов (связки 1-6).

```bash
helm repo add robusta https://robusta-charts.storage.googleapis.com
helm repo update

kubectl create namespace holmes
kubectl apply -f k8s/holmes-llm-credentials.yaml

helm upgrade --install holmes robusta/holmes \
  --namespace holmes --version 0.42.0 --wait \
  -f values/holmes-values.yaml \
  --set 'extraEnvVarsSecrets[0]=holmes-llm-credentials' \
  --set 'modelList.weak.model=openai/deepseek/deepseek-v4.1-flash' \
  --set 'modelList.weak.api_key=envRef:OPENAI_API_KEY' \
  --set 'modelList.weak.api_base=envRef:OPENAI_API_BASE'
```

Проверка, что кластер виден только через MCP: в логах пода Holmes остаются
включёнными `radar`, `internet`, `skills`, `connectivity_check` и внутренний
`core_investigation`; `kubernetes/*`, `prometheus/metrics`, `bash`, `helm/core`,
`kubectl-run` — выключены.

### 5. Mattermost

Mattermost Team Edition ставится через **Mattermost Operator**, БД — внешний
PostgreSQL (CloudNativePG). Сначала PostgreSQL, затем Mattermost. Версии:
`mattermost-operator 1.0.5` (operator `1.25.4`), образ
`mattermost/mattermost-team-edition:11.11.1`.

Namespace и bot token (token применяется до установки Mattermost):

```bash
kubectl create namespace mattermost
kubectl apply -f k8s/mattermost-bot-token.yaml
```

Внешний доступ — Traefik:

```bash
LB_IP="$(terraform output -raw ingress_public_ip)"

helm upgrade --install traefik oci://ghcr.io/traefik/helm/traefik \
  --namespace traefik --create-namespace --version 41.6.1 --wait \
  --set "service.spec.loadBalancerIP=${LB_IP}"
```

PostgreSQL — CloudNativePG в namespace `mattermost` (ставится первым):

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg --create-namespace --version 0.29.1 --wait

kubectl apply -f k8s/mattermost-postgres.yaml
kubectl wait --for=condition=Ready cluster/mm-pg -n mattermost --timeout=600s
```

Mattermost Team Edition — оператор:

```bash
helm repo add mattermost https://helm.mattermost.com
helm repo update

helm upgrade --install mattermost-operator mattermost/mattermost-operator \
  --namespace mattermost --version 1.0.5 --wait
```

Custom Resource `Mattermost` (host и пароль БД подставляются из кластера):

```bash
bash k8s/mattermost-apply.sh
kubectl wait --for=jsonpath='{.status.state}'=stable mattermost/mattermost -n mattermost --timeout=600s
```

`k8s/mattermost-apply.sh` создаёт Secret `mattermost-db` из секрета CloudNativePG
`mm-pg-app` и применяет CR `k8s/mattermost.yaml.tpl`. В CR:
`fileStore.local` с `accessModes: ReadWriteOnce` (диски `yc-network-hdd` только
RWO), `podTemplate.securityContext.fsGroup: 2000` (образ работает под uid/gid
`2000`, иначе `permission denied` на PVC), `ingress.ingressClass: traefik`.
`mattermostEnv` разрешает создание ботов и access-токенов
(`MM_SERVICESETTINGS_ENABLEBOTACCOUNTCREATION`, `MM_SERVICESETTINGS_ENABLEUSERACCESSTOKENS`).

Mattermost доступен по адресу `terraform output -raw mattermost_url`
(`http://mattermost.<IP>.sslip.io`); проверка — `/api/v4/system/ping` возвращает
`{"status":"OK"}`.

### 5.1. Демо-сущности (админ, канал, бот)

Через `mattermostEnv`/CR задаются только настройки сервера. Пользователь, команда,
канал и бот — это записи в БД, в `config.json` их нет; создаются через API или
`mmctl`. `mmctl` есть в образе и работает в local mode (`--local`, unix-сокет, без
пароля). Команда `bot create` в local mode запрещена, поэтому бот создаётся как
`user create` → `user convert --bot` → `token generate`.

```bash
ADMIN_PASSWORD='...' BOT_PASSWORD='...' bash k8s/mattermost-demo-setup.sh
```

`k8s/mattermost-demo-setup.sh` идемпотентно создаёт системного админа
(`admin@example.com`), команду `demo`, канал `#holmes-demo`, бота `holmes-bot`,
добавляет бота в команду и канал и кладёт выпущенный токен в Secret
`mattermost-bot-token`. Пароли передаются через переменные окружения, в репозитории
не хранятся.

Первый пользователь в свежем Mattermost тоже становится админом, но скрипт создаёт
его заранее через `mmctl --local` — вручную регистрироваться в UI не нужно.

Секрет `mattermost-bot-token` создаётся Terraform в `k8s/mattermost-bot-token.yaml`
(в `.gitignore`, в git не попадает) и применяется на шаге 5. Скрипт перезаписывает
его актуальным токеном из этого Mattermost: токен из `terraform.tfvars` — для
внешнего бота, в свежем инстансе его нет.

### 6. 16 приложений

```bash
helm upgrade --install bench-apps ./chart --namespace apps --create-namespace
```

Часть приложений падает — это специально: с багами пишутся и код, и values
(спека, раздел «Стенд»). `helm` при этом завершается с ошибкой, релиз `bench-apps`
получает статус `failed`, но 13 из 16 Deployment создаются. Причина падения
установки — `requests` больше `limits` у `nuxt-4` (memory 64Mi > 32Mi), `java-4`
(memory 256Mi > 96Mi), `java-3` (cpu 50m > 20m): API-сервер не принимает такие
Deployment. Это часть тестового стенда, отдельно не чинится.

## Проверка после каждого шага

```bash
kubectl get pods -A
kubectl describe pod -n <ns> <pod>
kubectl logs -n <ns> <pod>
```

## Прогоны бенчмарка

Каждый прогон — 16 инцидентов на одну связку MCP. Симптом — «приложение X
недоступно» (`go-1`…`python-4`). Считаются доля верных, токены и переполнение
контекста.

Связки (спека, раздел «Прогоны»):

| # | Radar | VictoriaMetrics | GitHub MCP | VictoriaLogs MCP |
|---|-------|-----------------|------------|------------------|
| 1 | да    | —               | —          | —                |
| 2 | да    | да              | —          | —                |
| 3 | да    | —               | да         | —                |
| 4 | да    | да              | да         | —                |
| 5 | да    | да              | —          | да               |
| 6 | да    | да              | да         | да               |

Раннер `bench/run_bundle.py` переключает стенд в нужную связку (`helm upgrade`
Radar и Holmes), прогоняет 16 симптомов через HTTP API HolmesGPT и складывает
ответы и токены в `/tmp/holmesgpt-bench/<связка>/`:

```bash
python3 bench/run_bundle.py 1     # связка 1, результаты в /tmp/holmesgpt-bench/bundle-1
python3 bench/run_bundle.py 6     # связка 6
```

Ответ и токены каждого инцидента — в `<app>.json`; сводка — в `summary.json`
(`total_tokens`, `prompt_tokens`, `completion_tokens`, `errors`). Источник цифр —
ответ `/api/chat`: `analysis` (ответ слабой модели) и `metadata.usage` (токены).
Вердикт «верно/неверно» раннер не ставит — это дело судьи.

Связки 3, 4, 6 требуют `github_token` в `terraform.tfvars` и секрет
`github-mcp-token` в namespace `holmes`. Связки 5, 6 требуют установленный
VictoriaLogs MCP.

## Демо Mattermost

Зайти в канал `#holmes-demo` под своим пользователем, тегнуть бота как обычного
пользователя. Бот забирает сообщение, отдаёт его в HTTP API HolmesGPT и пишет ответ
в тред. Для демо — один Go-инцидент. Скриншот добавляет человек перед публикацией.

<!-- скриншот демо -->
