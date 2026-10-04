variable "folder_id" {
  type        = string
  description = "Yandex Cloud folder id"
}

variable "llm_base_url" {
  type        = string
  description = "OpenAI-совместимый base URL для слабой модели и судьи"
}

variable "llm_api_key" {
  type        = string
  description = "Ключ LLM, общий для слабой модели и судьи"
  sensitive   = true
}

variable "mattermost_bot_token" {
  type        = string
  description = "Bot token для демо в Mattermost"
  sensitive   = true
}

variable "github_token" {
  type        = string
  description = "Read-only GitHub PAT для GitHub MCP (связки 3, 4, 6). Пусто — GitHub MCP не подключается."
  sensitive   = true
  default     = ""
}
