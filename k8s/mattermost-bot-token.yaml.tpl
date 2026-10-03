apiVersion: v1
kind: Secret
metadata:
  name: mattermost-bot-token
  namespace: mattermost
type: Opaque
stringData:
  bot-token: "${mattermost_bot_token}"
