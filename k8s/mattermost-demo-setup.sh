#!/usr/bin/env bash
# Создание демо-сущностей Mattermost через mmctl --local.
#
# Через mattermostEnv в CR задаются только настройки сервера (например
# MM_SERVICESETTINGS_ENABLEBOTACCOUNTCREATION). Сами сущности — пользователь,
# команда, канал, бот — в config.json не живут, это записи в БД. Их создаёт
# только API/mmctl; этот скрипт делает это идемпотентно.
#
# mmctl внутри пода работает в local mode (unix-сокет, без пароля). Команда
# `bot create` в local mode запрещена, поэтому бот делается так:
# `user create` -> `user convert --bot` -> `token generate`.
#
# Переменные окружения (пароли не хранятся в репозитории):
#   ADMIN_USER / ADMIN_EMAIL / ADMIN_PASSWORD  — системный админ (для входа)
#   BOT_USER                                   — имя бота
#   TEAM / CHANNEL                             — команда и канал #holmes-demo
set -euo pipefail

cd "$(dirname "$0")/.."

NS="${NS:-mattermost}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
BOT_USER="${BOT_USER:-holmes-bot}"
BOT_PASSWORD="${BOT_PASSWORD:-}"
TEAM="${TEAM:-demo}"
CHANNEL="${CHANNEL:-holmes-demo}"

if [[ -z "${ADMIN_PASSWORD}" || -z "${BOT_PASSWORD}" ]]; then
  echo "Задайте ADMIN_PASSWORD и BOT_PASSWORD в окружении" >&2
  exit 1
fi

POD="$(kubectl get pod -n "${NS}" -l installation.mattermost.com/installation -o jsonpath='{.items[0].metadata.name}')"
mmctl() { kubectl exec -n "${NS}" "${POD}" -- /mattermost/bin/mmctl "$@" --local; }

# Ошибки "уже существует" — ожидаемы при повторном запуске, прочие — нет.
run_idempotent() {
  local out
  if ! out="$(mmctl "$@" 2>&1)"; then
    case "${out}" in
      *"already exists"*|*"already been taken"*|*"already in"*|*"is not on this team"*) ;;
      *) echo "${out}" >&2; return 1 ;;
    esac
  fi
}

echo "== Админ ${ADMIN_USER} =="
run_idempotent user create --email "${ADMIN_EMAIL}" --username "${ADMIN_USER}" \
  --password "${ADMIN_PASSWORD}" --system-admin --email-verified --disable-welcome-email

echo "== Команда ${TEAM} и канал #${CHANNEL} =="
run_idempotent team create --name "${TEAM}" --display-name "${TEAM}"
run_idempotent channel create --team "${TEAM}" --name "${CHANNEL}" --display-name "Holmes Demo"

echo "== Бот ${BOT_USER} =="
run_idempotent user create --email "${BOT_USER}@example.com" --username "${BOT_USER}" \
  --password "${BOT_PASSWORD}" --email-verified --disable-welcome-email
if mmctl bot list 2>/dev/null | grep -q ": ${BOT_USER}("; then
  echo "Уже бот — конвертация не нужна"
else
  run_idempotent user convert "${BOT_USER}" --bot
fi
run_idempotent team users add "${TEAM}" "${BOT_USER}"
run_idempotent channel users add "${TEAM}:${CHANNEL}" "${BOT_USER}"

echo "== Токен бота =="
IDS="$(mmctl token list "${BOT_USER}" 2>/dev/null | awk -F: '/^[a-z0-9]+:/{print $1}' | tr '\n' ' ' || true)"
if [[ -n "${IDS// }" ]]; then
  mmctl token revoke ${IDS} >/dev/null
fi
TOKEN="$(mmctl token generate "${BOT_USER}" holmes-demo | cut -d: -f1)"
kubectl create secret generic mattermost-bot-token -n "${NS}" \
  --from-literal=bot-token="${TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Готово. Админ: ${ADMIN_USER} / ${ADMIN_EMAIL}; бот ${BOT_USER}, токен в секрете mattermost-bot-token."
