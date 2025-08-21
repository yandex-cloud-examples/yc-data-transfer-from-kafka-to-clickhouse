# Infrastructure for the Yandex Cloud Managed Service for Apache Kafka®, Managed Service for ClickHouse®, and Data Transfer
#
# RU: https://yandex.cloud/ru/docs/data-transfer/tutorials/mkf-to-mch
# EN: https://yandex.cloud/en/docs/data-transfer/tutorials/mkf-to-mch
#
# Configure the parameters of the source and target clusters:

locals {
  # Source cluster settings:
  source_user_producer     = "" # Name of the producer
  source_password_producer = "" # Password of the producer
  source_user_consumer     = "" # Name of the consumer
  source_password_consumer = "" # Password of the consumer
  source_topic_name        = "" # Topic name
  #source_endpoint_id       = "" # Source endpoint ID

  # Target database settings:
  target_db_name  = "" # Database name
  target_user     = "" # Username
  target_password = "" # User's password

  # The following settings are predefined. Change them only if necessary.
  network_name         = "network"                  # Name of the network
  subnet_name          = "subnet-a"                 # Name of the subnet
  source_cluster_name  = "kafka-cluster"            # Name of the Apache Kafka® cluster
  target_cluster_name  = "clickhouse-cluster"       # Name of the ClickHouse® cluster
  target_endpoint_name = "mch-target"               # Name of the target endpoint for the Managed Service for Apache Kafka® cluster
  transfer_name        = "transfer-from-mkf-to-mch" # Name of the transfer between the Managed Service for Apache Kafka® to the Managed Service for ClickHouse®
}

# Network infrastructure

resource "yandex_vpc_network" "network" {
  description = "Network for the Managed Service for Apache Kafka® and Managed Service for ClickHouse® clusters"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

resource "yandex_vpc_security_group" "security-group" {
  description = "Security group for the Managed Service for Apache Kafka® and Managed Service for ClickHouse® clusters"
  network_id  = yandex_vpc_network.network.id

  ingress {
    description    = "Allow connections to the Managed Service for Apache Kafka® cluster from the Internet"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 9091
    to_port        = 9092
  }

  ingress {
    description    = "Allow connections with clickhouse-client to the Managed Service for ClickHouse® cluster from the Internet"
    protocol       = "TCP"
    port           = 9440
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow HTTP connections to the Managed Service for ClickHouse® cluster from the Internet"
    protocol       = "TCP"
    port           = 8443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "The rule allows all outgoing traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "kafka-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  name               = local.source_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_security_group.security-group.id]

  config {
    brokers_count    = 1
    version          = "3.5"
    zones            = ["ru-central1-a"]
    assign_public_ip = true
    kafka {
      resources {
        resource_preset_id = "s2.micro" # 2 vCPU, 8 GB RAM
        disk_type_id       = "network-hdd"
        disk_size          = 10 # GB
      }
      kafka_config {}
    }
  }

  depends_on = [
    yandex_vpc_subnet.subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "source-topic" {
  cluster_id         = yandex_mdb_kafka_cluster.kafka-cluster.id
  name               = local.source_topic_name
  partitions         = 2
  replication_factor = 1
}

# User of the Managed service for the Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "user-producer" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.source_user_producer
  password   = local.source_password_producer
  permission {
    topic_name = yandex_mdb_kafka_topic.source-topic.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# User of the Managed service for the Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "user-consumer" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.source_user_consumer
  password   = local.source_password_consumer
  permission {
    topic_name = yandex_mdb_kafka_topic.source-topic.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
}

# Infrastructure for the Managed Service for ClickHouse® cluster

resource "yandex_mdb_clickhouse_cluster" "clickhouse-cluster" {
  description        = "Managed Service for ClickHouse® cluster"
  name               = local.target_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_security_group.security-group.id]

  clickhouse {
    resources {
      resource_preset_id = "s2.micro" # 2 vCPU, 8 GB RAM
      disk_type_id       = "network-ssd"
      disk_size          = 10 # GB
    }
  }

  host {
    type             = "CLICKHOUSE"
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.subnet-a.id
    assign_public_ip = true # Required for connection from the Internet
  }

  lifecycle {
    ignore_changes = [database, user,]
  }
}

resource "yandex_mdb_clickhouse_database" "db" {
  cluster_id = yandex_mdb_clickhouse_cluster.clickhouse-cluster.id
  name       = local.target_db_name
}

resource "yandex_mdb_clickhouse_user" "user" {
  cluster_id = yandex_mdb_clickhouse_cluster.clickhouse-cluster.id
  name       = local.target_user
  password   = local.target_password

  permission {
    database_name = yandex_mdb_clickhouse_database.db.name
  }
}

# Data Transfer infrastructure

#resource "yandex_datatransfer_endpoint" "mch-target" {
#  description = "Target endpoint for the Managed Service for ClickHouse® cluster"
#  name        = local.target_endpoint_name
#  settings {
#    clickhouse_target {
#      connection {
#        connection_options {
#          mdb_cluster_id = yandex_mdb_clickhouse_cluster.clickhouse-cluster.id
#          database       = local.target_db_name
#          user           = local.target_user
#          password {
#            raw = local.target_password
#          }
#        }
#      }
#      cleanup_policy = "CLICKHOUSE_CLEANUP_POLICY_DROP"
#    }
#  }
#}

#resource "yandex_datatransfer_transfer" "mysql-transfer" {
#  description = "Transfer from the Managed Service for Apache Kafka® to the Managed Service for ClickHouse®"
#  name        = local.transfer_name
#  source_id   = local.source_endpoint_id
#  target_id   = yandex_datatransfer_endpoint.mch-target.id
#  type        = "INCREMENT_ONLY" # Replicate data from the source Apache Kafka® topics
#}
