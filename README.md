# holmesgpt-mem0-qdrant-radar

Бенчмарк HolmesGPT на Yandex Managed Kubernetes. Схема и прогоны — в
[docs/superpowers/specs/2026-10-03-holmesgpt-bench-design.md](docs/superpowers/specs/2026-10-03-holmesgpt-bench-design.md).
Правила проекта — в [AGENTS.md](AGENTS.md).

## Требования

- [yc CLI](https://yandex.cloud/ru/docs/cli/), аутентифицированный (`yc init`)
- Terraform >= 1.3, kubectl, Helm >= 3

## Секреты (terraform.tfvars, в git не попадает)

Кластер создаётся Terraform. Base URL, ключ и bot token берутся из
`terraform.tfvars` и в репозиторий не копируются:

```hcl
folder_id              = "b1gxxxxxxxxxxxxxxxx"
llm_base_url           = "..."   # OpenAI-совместимый base URL слабой модели и судьи
llm_api_key            = "..."   # ключ LLM, общий для слабой модели и судьи
mattermost_bot_token   = "..."
```

Секреты `holmes-llm-credentials` и `mattermost-bot-token` генерируются Terraform из
`llm_api_key`, `llm_base_url` и `mattermost_bot_token` в файлы
`k8s/holmes-llm-credentials.yaml` и `k8s/mattermost-bot-token.yaml` (в `.gitignore`, в
git не попадают) и применяются в кластер через `kubectl apply -f`.

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

### 3. Radar

`skyhook/radar 1.15.0`, MCP включён. VictoriaMetrics подключается через
`traffic.prometheusUrl` (связки 2, 4, 5, 6). Radar не читает VictoriaLogs — логи
приложений он берёт из Kubernetes.

```bash
helm upgrade --install radar oci://ghcr.io/skyhook-io/charts/radar \
  --namespace radar --create-namespace --version 1.15.0 --wait \
  --set 'mcp.enabled=true' \
  --set 'traffic.prometheusUrl=http://vmsingle-vmks-victoria-metrics-k8s-stack.vmks.svc:8428'
```

### 4. HolmesGPT

`robusta/holmes 0.42.0`. MCP текущего прогона, модель из `terraform.tfvars`. Ключ и
base URL монтируются в под через Secret.

```bash
helm repo add robusta https://robusta-charts.storage.googleapis.com
helm repo update

kubectl create namespace holmes
kubectl apply -f k8s/holmes-llm-credentials.yaml

helm upgrade --install holmes robusta/holmes \
  --namespace holmes --version 0.42.0 --wait \
  --set 'extraEnvVarsSecrets[0]=holmes-llm-credentials' \
  --set 'modelList.weak.model=openai/qwen/qwen3.6-27b' \
  --set 'modelList.weak.api_key=envRef:OPENAI_API_KEY' \
  --set 'modelList.weak.api_base=envRef:OPENAI_API_BASE'
```

### 5. Mattermost

`mattermost-team-edition 6.6.108` — только демо, канал `#holmes-demo`, бот в треде.
Внешний доступ — через Traefik. В цифры бенчмарка не входит. Вход бота — bot token из
`terraform.tfvars`, не из репозитория.

```bash
helm repo add mattermost https://helm.mattermost.com
helm repo update

LB_IP="$(terraform output -raw ingress_public_ip)"

helm upgrade --install traefik oci://ghcr.io/traefik/helm/traefik \
  --namespace traefik --create-namespace --version 41.6.1 --wait \
  --set "service.spec.loadBalancerIP=${LB_IP}"

helm upgrade --install mattermost mattermost/mattermost-team-edition \
  --namespace mattermost --create-namespace --version 6.6.108 --wait \
  --set 'ingress.enabled=true' \
  --set 'ingress.className=traefik' \
  --set "ingress.hosts[0]=mattermost.${LB_IP}.sslip.io"
```

Mattermost доступен по адресу `terraform output -raw mattermost_url`
(`http://mattermost.<IP>.sslip.io`). Bot token не хранится в манифестах: секрет
`mattermost-bot-token` создаётся Terraform в `k8s/mattermost-bot-token.yaml`
(в `.gitignore`, в git не попадает) и применяется:

```bash
kubectl apply -f k8s/mattermost-bot-token.yaml
```

### 6. 16 приложений

```bash
helm upgrade --install bench-apps ./chart --namespace apps --create-namespace
```

## Проверка после каждого шага

```bash
kubectl get pods -A
kubectl describe pod -n <ns> <pod>
kubectl logs -n <ns> <pod>
```

## Демо Mattermost

Зайти в канал `#holmes-demo` под своим пользователем, тегнуть бота как обычного
пользователя. Бот забирает сообщение, отдаёт его в HTTP API HolmesGPT и пишет ответ
в тред. Для демо — один Go-инцидент. Скриншот добавляет человек перед публикацией.

<!-- скриншот демо -->
