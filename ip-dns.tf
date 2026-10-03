resource "yandex_vpc_address" "traefik" {
  name      = "bench-traefik-pip"
  folder_id = var.folder_id

  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

# Публичный DNS не требуется: используются sslip.io-имена вида
# <сервис>.<LB_IP>.sslip.io, которые резолвятся в IP балансировщика Traefik.
output "ingress_public_ip" {
  description = "Публичный IP балансировщика Traefik"
  value       = yandex_vpc_address.traefik.external_ipv4_address[0].address
}

output "mattermost_url" {
  description = "URL Mattermost (sslip.io из публичного IP балансировщика Traefik)"
  value       = "http://mattermost.${yandex_vpc_address.traefik.external_ipv4_address[0].address}.sslip.io"
}
