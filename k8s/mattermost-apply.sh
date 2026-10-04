#!/usr/bin/env bash
# Применение Mattermost через Mattermost Operator.
#
# Создаёт Secret mattermost-db из данных CloudNativePG (mm-pg-app) и применяет
# Custom Resource Mattermost с host'ом из terraform output. Пароль БД берётся из
# кластера в момент запуска, в репозиторий не попадает.
set -euo pipefail

cd "$(dirname "$0")/.."

NS=mattermost
PG_SECRET=mm-pg-app
DB_SECRET=mattermost-db
CR_TEMPLATE=k8s/mattermost.yaml.tpl

MATTERMOST_HOST="mattermost.$(terraform output -raw ingress_public_ip).sslip.io"
PG_PW="$(kubectl get secret "${PG_SECRET}" -n "${NS}" -o jsonpath='{.data.password}' | base64 -d)"
DSN="postgres://mattermost:${PG_PW}@mm-pg-rw.${NS}.svc:5432/mattermost?sslmode=disable"

kubectl create secret generic "${DB_SECRET}" -n "${NS}" \
  --from-literal=DB_CONNECTION_STRING="${DSN}" \
  --from-literal=MM_SQLSETTINGS_DATASOURCE="${DSN}" \
  --dry-run=client -o yaml | kubectl apply -f -

MATTERMOST_HOST="${MATTERMOST_HOST}" envsubst '${MATTERMOST_HOST}' <"${CR_TEMPLATE}" | kubectl apply -f -
