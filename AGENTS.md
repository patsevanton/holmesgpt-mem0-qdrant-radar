# Правила проекта

Бенчмарк HolmesGPT на Yandex Managed Kubernetes. Схема и прогоны — в
[docs/superpowers/specs/2026-10-03-holmesgpt-bench-design.md](docs/superpowers/specs/2026-10-03-holmesgpt-bench-design.md).

## Коммиты

- Названия коммитов — существительное/отглагольное существительное, не инфинитив.
- Префикс `feat:` обязателен для изменений кода приложений и Dockerfile: CI
  (`huggingface/semver-release-action`) бампит версию образа только по `feat:`/`fix:`.
  Без префикса релиза нет, образы в GHCR не собираются. Остальные изменения
  (`docs:`, `chore:`, `ci:`) релиз не создают.
- Версия образов единая для всех 16 приложений: CI пушит их под одним тегом
  `steps.semver.outputs.version`. После релиза `imageTag` в `chart/values.yaml`
  проставляется на эту версию.

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

## Инфраструктура

```bash
terraform init
eval "$(terraform output -raw k8s_cluster_credentials_command)"
kubectl get nodes
```

Ноды preemptible, диск HDD, без публичного IP; egress — NAT Gateway и route table.
Версию Kubernetes без явного указания не менять.

## Порядок установки стенда

Строгий порядок: vmks создаёт CRD оператора и vmagent.

1. **VictoriaMetrics** (`victoria-metrics-k8s-stack 0.95.0`) в namespace `vmks`.
   В values отключены scrape-job и recording-правила control-plane Yandex Managed K8s
   (`kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, группы `etcd`,
   `kubernetes-system-scheduler`, `kubernetes-system-controller-manager`,
   `kube-scheduler.rules`): master управляемый и вне кластера.

   ```bash
   helm upgrade --install vmks oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack \
     --namespace vmks --create-namespace --version 0.95.0 --wait -f values/vmks-values.yaml
   ```

2. **VictoriaLogs** (`victoria-logs-single 0.13.10`) в namespace `vmks` + коллектор
   логов. Логи всех подов уходят в VictoriaLogs.

3. **Radar** (`skyhook/radar 1.15.0`), MCP включён. VictoriaMetrics подключается
   через `traffic.prometheusUrl` (связки 2, 4, 5, 6). Radar не читает VictoriaLogs —
   логи приложений он берёт из Kubernetes.

4. **HolmesGPT** (`robusta/holmes 0.42.0`). MCP текущего прогона, модель из
   `terraform.tfvars`. Секрет с ключом монтируется в под.

5. **Mattermost** — демо, канал `#holmes-demo`, бот в треде. В цифры бенчмарка не
   входит. Ставится **Mattermost Operator** (`mattermost-operator 1.0.5`, образ
   `mattermost/mattermost-team-edition:11.11.1`). Порядок: bot token → Traefik →
   CloudNativePG (PostgreSQL, ставится первым) → оператор → CR `Mattermost`
   (`bash k8s/mattermost-apply.sh`).

6. **16 приложений** из `chart/`:

   ```bash
   helm upgrade --install bench-apps ./chart --namespace apps --create-namespace
   ```

## Проверка после каждого шага

```bash
kubectl get pods -A
kubectl describe pod -n <ns> <pod>
kubectl logs -n <ns> <pod>
```
