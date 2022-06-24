provider "vsphere" {
  vsphere_server = var.vsphere_server
  user           = var.vsphere_user
  password       = var.vsphere_password

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "host" {
  name          = var.host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  count         = length(var.vm_config)
  name          = var.vm_config[count.index].network
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "local_file" "seed-config-user" {
  count = length(var.vm_config)
  content = templatefile("cloud-init/user-data", merge({
    name       = format("%s%02d", var.vm_name, count.index)
    vm_user    = var.vm_user
    vm_ssh_pub = var.vm_ssh_pub
    dns        = var.dns
  }, var.vm_config[count.index]))
  filename = format("cloud-init-workdir/user-data-%02d", count.index)
}

resource "local_file" "seed-config-network" {
  count = length(var.vm_config)
  content = templatefile("cloud-init/network-config", merge({
    name       = format("%s%02d", var.vm_name, count.index)
    vm_user    = var.vm_user
    vm_ssh_pub = var.vm_ssh_pub
    dns        = var.dns
  }, var.vm_config[count.index]))
  filename = format("cloud-init-workdir/network-config-%02d", count.index)
}

resource "local_file" "seed-config-meta" {
  count = length(var.vm_config)
  content = templatefile("cloud-init/meta-data", merge({
    name       = format("%s%02d", var.vm_name, count.index)
    vm_user    = var.vm_user
    vm_ssh_pub = var.vm_ssh_pub
    dns        = var.dns
  }, var.vm_config[count.index]))
  filename = format("cloud-init-workdir/meta-data-%02d", count.index)
}

resource "local_file" "set_initial_state" {
  content  = "0"
  filename = "cloud-init-workdir/initial_state.txt"
}

resource "null_resource" "seed-iso" {
  count = length(var.vm_config)
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    # ((c++)) && ((c==180)) && break;
    command = "while [[ $(cat ${local_file.set_initial_state.filename}) != \"${count.index}\" ]]; do echo \"${count.index} is asleep...\";sleep 5;done"
  }

  provisioner "local-exec" {
    command = <<COMMAND
      cp ${local_file.seed-config-user[count.index].filename} cloud-init-workdir/user-data
      cp ${local_file.seed-config-meta[count.index].filename} cloud-init-workdir/meta-data
      cp ${local_file.seed-config-network[count.index].filename} cloud-init-workdir/network-config
      mkisofs -o cloud-init-workdir/seed-${count.index}.iso -volid cidata -joliet -rock cloud-init-workdir/{meta-data,user-data,network-config}
      rm cloud-init-workdir/{meta-data,user-data,network-config}
    COMMAND
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "echo \"${count.index + 1}\" > cloud-init-workdir/initial_state.txt"
  }

  # Requires terraform 0.12.23+ for issue #24139 fix (for_each destroy provisioner in module)
  provisioner "local-exec" {
    when       = destroy
    command    = "rm cloud-init-workdir/seed-${count.index}.iso"
    on_failure = continue
  }
  depends_on = [
    local_file.seed-config-user,
    local_file.seed-config-meta,
    local_file.seed-config-network,
    local_file.set_initial_state
  ]
}

resource "vsphere_file" "seed-iso" {
  count            = length(var.vm_config)
  datacenter       = var.datacenter
  datastore        = var.datastore
  source_file      = "cloud-init-workdir/seed-${count.index}.iso"
  destination_file = format("seeds/%s%02d-seed.iso", var.vm_name, count.index)

  depends_on = [
    null_resource.seed-iso
  ]
}

resource "vsphere_virtual_machine" "photonvms" {
  count            = length(var.vm_config)
  name             = format("%s%02d", var.vm_name, count.index)
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  datacenter_id    = data.vsphere_datacenter.dc.id
  host_system_id   = data.vsphere_host.host.id
  num_cpus         = 2
  memory           = 4096

  network_interface {
    network_id = data.vsphere_network.network[count.index].id
  }

  # wait_for_guest_net_timeout = -1
  # wait_for_guest_ip_timeout  = -1

  cdrom {
    datastore_id = data.vsphere_datastore.datastore.id
    path         = vsphere_file.seed-iso[count.index].destination_file
  }

  ovf_deploy {
    allow_unverified_ssl_cert = false
    local_ovf_path            = var.ova_path
    disk_provisioning         = "thin"
    ip_protocol               = "IPV4"
    ip_allocation_policy      = "STATIC_MANUAL"
  }

  firmware                = "efi"
  efi_secure_boot_enabled = true

  guest_id = "vmwarePhoton64Guest"
}

resource "local_file" "k3s-provision" {
  content = templatefile("cloud-init/k3s-provision.sh", merge({
    vm_user   = var.vm_user
    vm_config = var.vm_config
  }))
  filename = "cloud-init-workdir/k3s-provision.sh"

  provisioner "local-exec" {
    command = "bash -c './cloud-init-workdir/k3s-provision.sh --ssh-key ${var.ssh_key_file}'"
  }
  depends_on = [
    vsphere_virtual_machine.photonvms
  ]
}

output "vm_ips" {
  value = vsphere_virtual_machine.photonvms.*.guest_ip_addresses
}

output "z_kubectl_command" {
  value = "KUBECONFIG=kubeconfig kubectl get nodes"
}
