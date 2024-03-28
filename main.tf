provider "google" {
  project = var.project_id
  region = var.region
}
data "google_compute_zones" "this" {
  region  = var.region
  project = var.project_id
}
# creating vpc
resource "google_compute_network" "vpc" {
  name  =  var.vpc_name
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
  routing_mode = var.routing_mode
}
# creating subnets

resource "google_compute_subnetwork" "webapp_subnet" {
  name = "${var.vpc_name}-webapp"
  region = var.region
  network = google_compute_network.vpc.id
 ip_cidr_range = var.webapp_subnet_cidr
 private_ip_google_access = false
}

resource "google_compute_subnetwork" "db_host" {
  name = "${var.vpc_name}-db"
  region = var.region
  network = google_compute_network.vpc.id
  ip_cidr_range = var.db_subnet_cidr
  private_ip_google_access = false
  
}

#creating routes
resource "google_compute_route" "internet_access" {
  name = "${var.vpc_name}-internet-access"
  network = google_compute_network.vpc.id
  dest_range = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority = 900
  depends_on = [ google_compute_subnetwork.webapp_subnet ]
}


resource "google_compute_firewall" "allow_web" {
  name = "${var.vpc_name}-allow-web"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports = [var.app_port]
  }
  source_ranges = ["0.0.0.0/0"]

}

resource "google_compute_firewall" "block_ssh" {
  name ="${var.vpc_name}-block-ssh"
  network = google_compute_network.vpc.name

  deny {
    protocol = "tcp"
    ports = ["22"]

  }
  source_ranges = [ "0.0.0.0/0" ]
  priority = 1000
  
}


resource "google_compute_instance" "vm_instance" {
  name = var.vm_name
  zone = var.vm_zone
  machine_type = var.vm_machine_type

  boot_disk {
    initialize_params {
      image = var.vm_image
      type = var.vm_disk_type
      size = var.vm_disk_size_gb
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.webapp_subnet.id
    # network = google_compute_network.this.name

      access_config{
        nat_ip = google_compute_address.static_ip.address
    
  }
  }
  # service_account {
  #   scopes = ["cloud-platform"]
  #   email = var.email
  # }

 metadata = {
    startup-script = "#!/bin/bash\n  cat<<EOF>/opt/web-app/.env\n  DB_HOST = ${google_sql_database_instance.cloudsql_instance.private_ip_address}\n  DB_NAME = webapp\n  DB_USER= webapp\n  DB_PASSWORD= ${random_password.password.result}\n  DB_PORT= 3306\n  EOF\n\n  chown csye6225:csye6225 /opt/web-app/.env\n  chmod 600 /opt/web-app/.env\n  systemctl restart web-app\n\n  EOT\n"
  }
  service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["cloud-platform"]
  }

}

resource "google_project_service" "service_networking" {
  service = "servicenetworking.googleapis.com"
  project = var.project_id
}

resource "google_compute_global_address" "private_ip_range" {
  provider = google-beta
  project = var.project_id
  name = "google-managed-services-${var.vpc_name}"
  purpose = "VPC_PEERING"
  address_type = "INTERNAL"
  prefix_length = 24
  network = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network = google_compute_network.vpc.id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [ google_compute_global_address.private_ip_range.name ]
  deletion_policy = "ABANDON"
  # depends_on = [ google_project_service.service_networking ]
  }
 



resource "google_sql_database_instance" "cloudsql_instance" {
  provider = google-beta
  project = var.project_id
  # name = "${var.cloudsql_instance_name}"
  name = var.cloudsql_instance_name
  database_version = var.cloudsql_database_version
  region = "${var.region}"
  deletion_protection = false

  settings {
    tier = var.cloudsql_instance_tier
    ip_configuration {
      ipv4_enabled = false
      private_network = google_compute_network.vpc.self_link
      # require_ssl = var.cloudsql_require_ssl
      enable_private_path_for_google_cloud_services = true
    }
    disk_type = var.cloudsql_disk_type
    disk_size = var.cloudsql_disk_size
    disk_autoresize = var.cloudsql_disk_autoresize
    backup_configuration {
      enabled = true
      binary_log_enabled = true
    }
    availability_type = "REGIONAL"

    # database_flags {
    #    name  = "log_bin"
    #    value = "ON"
    # }
    #     database_flags {
    #     name  = "binlog_format"
    #     value = "ROW"
    #   }

  }
  depends_on = [google_service_networking_connection.private_vpc_connection]
}


resource "google_sql_database" "webapp_database" {
  name = "webapp"
  instance = google_sql_database_instance.cloudsql_instance.name
}


resource "random_password" "password" {
  length = 16
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "user" {
  name = "webapp"
  instance = google_sql_database_instance.cloudsql_instance.name
  password = random_password.password.result
  host = "%"
}

 output "cloudsql_private_ip" {
    value = "google_sql_database_instance.cloudsql_instance.ip_address"
  }

resource "google_compute_address" "static_ip" {
  name   = "vm-static-ip"
  region = var.region
}

resource "google_service_account" "vm_service_account" {
  account_id   = "vm-service-account"
  display_name = "Service Account for VM Instance"
  project = var.project_id
}
#IAM bindings to service account
resource "google_project_iam_binding" "logging_admin" {
  project = var.project_id
  role    = "roles/logging.admin"
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}",
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}",
  ]
}

data "google_dns_managed_zone" "my_dns_zone" {
  name        = "udaygattu"
}
 
resource "google_dns_record_set" "my_dns_record" {
  name         = data.google_dns_managed_zone.my_dns_zone.dns_name
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.my_dns_zone.name
  rrdatas      = [google_compute_address.static_ip.address]

}

