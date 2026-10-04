apiVersion: installation.mattermost.com/v1beta1
kind: Mattermost
metadata:
  name: mattermost
  namespace: mattermost
spec:
  image: mattermost/mattermost-team-edition
  version: "11.11.1"
  replicas: 1
  ingress:
    enabled: true
    host: ${MATTERMOST_HOST}
    ingressClass: traefik
  database:
    external:
      secret: mattermost-db
  fileStore:
    local:
      enabled: true
      storageSize: 10Gi
      accessModes:
        - ReadWriteOnce
  podTemplate:
    securityContext:
      fsGroup: 2000
  mattermostEnv:
    - name: MM_SERVICESETTINGS_ENABLEBOTACCOUNTCREATION
      value: "true"  # Разрешает юзерам создание bot-аккаунтов
    - name: MM_SERVICESETTINGS_ENABLEUSERACCESSTOKENS
      value: "true"  # Разрешает юзерам выпуск personal access tokens
