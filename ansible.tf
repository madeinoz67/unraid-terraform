# Onboard each built VM into Ansilume (ansible.lovegroove.io) at build time:
# 1. cloud-init injects the controller's key so Ansilume's runner can SSH in
# 2. this provisioner appends the host to a dedicated static inventory
# 3. launches the convergence job template limited to the new host
#
# Token lives in ~/.claude/.env as ANSILUME_API_TOKEN; base URL + inventory
# + template ids are inputs so the target instance can change without edits.

variable "ansilume_url" {
  type    = string
  default = "https://ansible.lovegroove.io"
}
variable "ansilume_inventory_id" {
  type        = number
  description = "Static inventory new hosts are appended to"
  default     = 4
}
variable "ansilume_baseline_template_id" {
  type        = number
  description = "Job template launched against the new host after enrollment"
  default     = 15 # Fleet — Common baseline (unraid VMs)
}
variable "ansilume_ssh_key_path" {
  type    = string
  default = "~/.ssh/ansible.pub"
}

# The controller's key rides into every VM next to the user's own key.
locals {
  ansilume_pub_key = file(pathexpand(var.ansilume_ssh_key_path))
}

resource "null_resource" "ansilume_onboard" {
  triggers = {
    host       = local.vm_full_name
    ip         = libvirt_domain.vm.network_interface[0].addresses[0]
    user       = var.user_name
    inventory  = var.ansilume_inventory_id
    template   = var.ansilume_baseline_template_id
    onboard_id = uuid() # run once per create
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      API="${var.ansilume_url}/api/v1"
      AUTH="Authorization: Bearer $ANSILUME_API_TOKEN"
      INV=${var.ansilume_inventory_id}
      HOST=${local.vm_full_name}
      IP=${libvirt_domain.vm.network_interface[0].addresses[0]}

      # current inventory content (YAML mapping)
      CONTENT=$(curl -sfS -H "$AUTH" "$API/inventories/$INV" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["content"])')

      # idempotent append: skip if host already in content
      if ! printf '%s' "$CONTENT" | grep -q "^    $HOST:"; then
        NEW=$(printf '%s' "$CONTENT" | python3 -c '
import sys, yaml
c = yaml.safe_load(sys.stdin.read()) or {}
c.setdefault("all", {}).setdefault("hosts", {})
c["all"]["hosts"]["'"$HOST"'"] = {"ansible_host": "'"$IP"'"}
print(yaml.safe_dump(c, default_flow_style=False, sort_keys=True))
')
        PAYLOAD=$(python3 -c 'import json,sys;print(json.dumps({"inventory_type":"static","content":sys.stdin.read()}))' <<< "$NEW")
        curl -sfS -X PUT -H "$AUTH" -H "Content-Type: application/json" -d "$PAYLOAD" "$API/inventories/$INV" >/dev/null
        echo "inventory: added $HOST ($IP)"
      else
        echo "inventory: $HOST already present"
      fi

      # launch convergence template limited to this host
      curl -sfS -X POST -H "$AUTH" -H "Content-Type: application/json" \
        -d "{\"job_template_id\": ${var.ansilume_baseline_template_id}, \"limit\": \"$HOST\"}" \
        "$API/jobs" >/dev/null
      echo "job: launched template ${var.ansilume_baseline_template_id} limit=$HOST"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
