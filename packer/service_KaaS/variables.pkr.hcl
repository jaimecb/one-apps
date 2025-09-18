variable "appliance_name" {
  type    = string
  default = "service_kaas"
}

variable "input_dir" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "headless" {
  type    = bool
  default = false
}

variable "version" {
  type    = string
  default = ""
}

variable "KaaS" {
  type = map(map(string))

  default = {
    "x86_64" = {
      iso_url = "export/alpine321.qcow2"
    }

    "aarch64" = {
      iso_url = "export/alpine321.aarch64.qcow2"
    }
  }
}
