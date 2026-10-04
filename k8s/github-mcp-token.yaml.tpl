apiVersion: v1
kind: Secret
metadata:
  name: github-mcp-token
  namespace: holmes
type: Opaque
stringData:
  token: "${github_token}"
