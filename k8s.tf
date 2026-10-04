resource "yandex_iam_service_account" "sa_k8s_editor" {
  folder_id = var.folder_id
  name      = "bench-sa-k8s-editor"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_k8s_editor_permissions" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa_k8s_editor.id}"
}

resource "time_sleep" "wait_sa" {
  create_duration = "20s"
  depends_on = [
    yandex_iam_service_account.sa_k8s_editor,
    yandex_resourcemanager_folder_iam_member.sa_k8s_editor_permissions
  ]
}

resource "yandex_kubernetes_cluster" "bench" {
  name       = "bench"
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.bench.id

  master {
    version = "1.33"
    regional {
      region = "ru-central1"
      location {
        zone      = yandex_vpc_subnet.bench_a.zone
        subnet_id = yandex_vpc_subnet.bench_a.id
      }
      location {
        zone      = yandex_vpc_subnet.bench_b.zone
        subnet_id = yandex_vpc_subnet.bench_b.id
      }
      location {
        zone      = yandex_vpc_subnet.bench_d.zone
        subnet_id = yandex_vpc_subnet.bench_d.id
      }
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.sa_k8s_editor.id
  node_service_account_id = yandex_iam_service_account.sa_k8s_editor.id
  release_channel         = "STABLE"

  depends_on = [
    time_sleep.wait_sa,
    time_sleep.wait_lb_release,
  ]
}

resource "yandex_kubernetes_node_group" "k8s_node_group" {
  name        = "bench-node-group"
  description = "Node group for the Managed Service for Kubernetes cluster"
  cluster_id  = yandex_kubernetes_cluster.bench.id
  version     = "1.33"

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    location { zone = yandex_vpc_subnet.bench_a.zone }
    location { zone = yandex_vpc_subnet.bench_b.zone }
    location { zone = yandex_vpc_subnet.bench_d.zone }
  }

  instance_template {
    platform_id = "standard-v3"
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      nat = false
      subnet_ids = [
        yandex_vpc_subnet.bench_a.id,
        yandex_vpc_subnet.bench_b.id,
        yandex_vpc_subnet.bench_d.id
      ]
    }
    resources {
      cores  = 4
      memory = 16
    }
    boot_disk {
      type = "network-hdd"
      size = 64
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.bench.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.bench.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}

provider "kubernetes" {
  host                   = yandex_kubernetes_cluster.bench.master[0].external_v4_endpoint
  cluster_ca_certificate = yandex_kubernetes_cluster.bench.master[0].cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["k8s", "create-token"]
    command     = "yc"
  }
}

output "k8s_cluster_credentials_command" {
  value = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.bench.id} --external --force"
}

output "nat_gateway_id" {
  value = yandex_vpc_gateway.nat.id
}
