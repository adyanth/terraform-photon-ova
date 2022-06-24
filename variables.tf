variable "vsphere_server" {
  description = "vSphere server"
  type        = string
}

variable "vsphere_user" {
  description = "vSphere username"
  type        = string
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  sensitive   = true
}

variable "datacenter" {
  description = "vSphere data center"
  type        = string
}

variable "cluster" {
  description = "vSphere cluster"
  type        = string
}

variable "datastore" {
  description = "vSphere datastore"
  type        = string
}

variable "host" {
  description = "vSphere host"
  type        = string
}

variable "ova_path" {
  description = "VM Template name (ie: image_path)"
  type        = string
}

variable "vm_name" {
  description = "New VM name"
  type        = string
}

variable "vm_user" {
  description = "VM username"
  type        = string
}

variable "vm_ssh_pub" {
  description = "SSH Public key to provision"
  type        = string
}

variable "ssh_key_file" {
  description = "SSH Private key file path corresponding to vm_ssh_pub"
  type        = string
  # default     = "~/.ssh/id_ed25519"
}

variable "dns" {
  description = "DNS Server to use"
  type        = string
  default     = "1.1.1.1"
}

variable "vm_config" {
  description = "Configuration per VM"
  type = list(object({
    network = string
    address = string
    gateway = string
  }))
  # default = [{
  #   network = "VM Network"
  #   address = "192.168.0.10"
  #   gateway = "192.168.0.1"
  # }]
}
