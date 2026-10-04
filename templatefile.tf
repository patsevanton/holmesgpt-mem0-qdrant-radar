resource "local_file" "holmes_llm_credentials" {
  content = templatefile("${path.module}/k8s/holmes-llm-credentials.yaml.tpl", {
    llm_api_key  = var.llm_api_key
    llm_base_url = var.llm_base_url
  })
  filename        = "${path.module}/k8s/holmes-llm-credentials.yaml"
  file_permission = "0600"
}

resource "local_file" "mattermost_bot_token" {
  content = templatefile("${path.module}/k8s/mattermost-bot-token.yaml.tpl", {
    mattermost_bot_token = var.mattermost_bot_token
  })
  filename        = "${path.module}/k8s/mattermost-bot-token.yaml"
  file_permission = "0600"
}

resource "local_file" "github_mcp_token" {
  count = var.github_token == "" ? 0 : 1

  content = templatefile("${path.module}/k8s/github-mcp-token.yaml.tpl", {
    github_token = var.github_token
  })
  filename        = "${path.module}/k8s/github-mcp-token.yaml"
  file_permission = "0600"
}
