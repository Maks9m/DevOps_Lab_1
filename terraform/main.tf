locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "local_file" "worker_cloudinit" {
  filename = "${abspath(path.module)}/.rendered/worker-cloudinit.yaml"
  content = templatefile("${path.module}/cloud-init/worker.yaml.tftpl", {
    ssh_public_key = local.ssh_public_key
  })
  file_permission = "0600"
}

resource "local_file" "db_cloudinit" {
  filename = "${abspath(path.module)}/.rendered/db-cloudinit.yaml"
  content = templatefile("${path.module}/cloud-init/db.yaml.tftpl", {
    ssh_public_key = local.ssh_public_key
  })
  file_permission = "0600"
}

resource "multipass_instance" "worker" {
  name           = var.worker_name
  cpus           = var.worker_cpus
  memory         = var.worker_memory
  disk           = var.worker_disk
  image          = var.image
  cloudinit_file = local_file.worker_cloudinit.filename
}

resource "multipass_instance" "db" {
  name           = var.db_name_vm
  cpus           = var.db_cpus
  memory         = var.db_memory
  disk           = var.db_disk
  image          = var.image
  cloudinit_file = local_file.db_cloudinit.filename

  # Serialize launches: Multipass DHCP races when two VMs come up in parallel
  # and can hand out the same IP. Forcing db to wait for worker avoids that.
  depends_on = [multipass_instance.worker]
}
