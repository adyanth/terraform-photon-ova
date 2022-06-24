#!/bin/sh

%{ for i, vm in vm_config ~}
%{~ if i == 0 }
k3sup install --context photon-k3s --user ${vm_user} --ip ${split("/", vm.address)[0]} "$@"
%{ else }
k3sup join --server-user ${vm_user} --user ${vm_user} --server-ip ${split("/", vm_config[0].address)[0]} --ip ${split("/", vm.address)[0]} "$@"
%{~ endif ~}
%{~ endfor }
