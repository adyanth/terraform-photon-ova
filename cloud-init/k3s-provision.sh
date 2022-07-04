#!/bin/sh

%{ for i, vm in vm_config ~}
%{~ if i == 0 }
k3s_master=${split("/", vm.address)[0]}
k3sup install --context photon-k3s --user ${vm_user} --ip $k3s_master "$@"
%{ else }
k3sup join --server-user ${vm_user} --user ${vm_user} --server-ip $k3s_master --ip ${split("/", vm.address)[0]} "$@"
%{~ endif ~}
%{~ endfor }

export KUBECONFIG=kubeconfig
kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch -n argocd svc argocd-server -p '{"spec": {"type": "NodePort"}}'

pods=$(kubectl -n argocd get pods -o=jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}{"\n"}' | tr " " "\n" | wc -l)
while [ $pods -ne 6 ]
do
  echo "Waiting for argocd to stabilize"
  sleep 5
  pods=$(kubectl -n argocd get pods -o=jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}{"\n"}' | tr " " "\n" | wc -l)
  echo "Pods up: $pods"
done

until kubectl -n argocd get secret argocd-initial-admin-secret
do
  echo "Waiting for argocd-initial-admin-secret"
  sleep 2
done

port=$(kubectl -n argocd get svc argocd-server -o=jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

argocd login $k3s_master:$port --insecure --username admin --password $password
argocd account update-password --current-password $password --new-password 'password'

echo "Open https://$k3s_master:$port in your browser and login with admin:password"
