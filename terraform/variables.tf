variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into both VMs for the 'ansible' user."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "image" {
  description = "Multipass Ubuntu image alias (e.g. '24.04', 'jammy', 'noble')."
  type        = string
  default     = "24.04"
}

variable "worker_name" {
  description = "Name of the worker VM (runs nginx + Flask)."
  type        = string
  default     = "lab4-worker"
}

variable "worker_cpus" {
  description = "vCPUs allocated to the worker VM."
  type        = number
  default     = 1
}

variable "worker_memory" {
  description = "Memory for the worker VM (Multipass size string, e.g. '1G')."
  type        = string
  default     = "1G"
}

variable "worker_disk" {
  description = "Disk size for the worker VM (Multipass size string)."
  type        = string
  default     = "5G"
}

variable "db_name_vm" {
  description = "Name of the database VM (runs MariaDB)."
  type        = string
  default     = "lab4-db"
}

variable "db_cpus" {
  description = "vCPUs allocated to the database VM."
  type        = number
  default     = 1
}

variable "db_memory" {
  description = "Memory for the database VM."
  type        = string
  default     = "1G"
}

variable "db_disk" {
  description = "Disk size for the database VM."
  type        = string
  default     = "5G"
}
