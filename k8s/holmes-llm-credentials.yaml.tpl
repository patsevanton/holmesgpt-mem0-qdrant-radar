apiVersion: v1
kind: Secret
metadata:
  name: holmes-llm-credentials
  namespace: holmes
type: Opaque
stringData:
  OPENAI_API_KEY: "${llm_api_key}"
  OPENAI_API_BASE: "${llm_base_url}"
