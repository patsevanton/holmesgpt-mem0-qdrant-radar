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
