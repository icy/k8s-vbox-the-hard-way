#!/usr/bin/env bash

# Purpose : Script to bootstrap k8s cluster the hard way with Virtualbox
# Author  : Ky-Anh Huynh
# License : MIT
# Date    : 2019-01-12

set -a # export all variables....
set -u # break if there is any unbound variable

_vagrant() { #public: A wrapper for `vagrant` command. E.g, `_vagrant destroy -f` to destroy all nodes.
  mkdir -pv "$D_MACHINES"
  for _node in $MACHINES; do
    mkdir -pv "$D_MACHINES/$_node/"
    cd "$D_MACHINES/$_node/" || return
    cp -fv "$F_VAGRANTFILE" Vagrantfile
    HOME="$OHOME" vagrant "$@" || return
  done

  if [[ "${1:-}" == "up" ]]; then
    _ssh_config_update_all
  fi
}

_ssh_config_update_all() {
  _ssh_config_generate > "$F_SSH_CONFIG.tmp"
  mv -fv "$F_SSH_CONFIG.tmp" "$F_SSH_CONFIG"
  _ssh_keyscan > "$F_SSH_KNOWN_HOSTS.tmp"
  mv -fv "$F_SSH_KNOWN_HOSTS.tmp" "$F_SSH_KNOWN_HOSTS"
}

_ssh_config_generate() {
  for _node in $MACHINES; do
    _index="${_node#*-}"
    _role="${_node%-*}"
    _ip="$IP_PREFIX.${_index}"
    _ssh_port="${SSH_PORT_PREFIX}${_index}"
    _message="_index: $_index, role: $_role, ip: $_ip, ssh_port: $_ssh_port"

    1>&2 echo "$_message"
    echo "## vagrant, $_message"
    echo "Host ${_role}-${_index} ${_role}${_index} ${_role:0:1}${_index} ip${_index} ${_index}"
    echo "  Hostname localhost"
    echo "  User vagrant"
    echo "  Port ${_ssh_port}"
    echo "  UserKnownHostsFile ${F_SSH_KNOWN_HOSTS}"
    echo "  StrictHostKeyChecking yes"
    echo "  IdentityFile $OHOME/.vagrant.d/insecure_private_key"
  done
}

_ssh_keyscan() {
  for _node in $MACHINES; do
    _index="${_node#*-}"
    _ip="$IP_PREFIX.${_index}"
    _ssh_port="10${_index}"
    ssh-keyscan -4 -p "$_ssh_port" localhost
    ssh-keyscan -4 -p "$_ssh_port" 127.0.0.1
  done
}

_ssh_list() { #public: List all nodes created by vagrant. Useful for `ssh`-related tasks.
  grep ^Host "$F_SSH_CONFIG" | column -t
}

## main

env_setup() {
  # K8s and vbox environments

  # Fast
  # Number of workers to start.
  N_WORKERS=1
  # Number of controllers. In production environment it's often 3.
  # We start with 2 to see how bad things can happen.
  N_CONTROLLERS=2

  # Slow
  # Memory size of worker and controller. For testing purpose we can
  # use smaller size for workers. For conconller smaller size (<1024)
  # may lead to OOM issue.
  MEM_WORKER="1024"
  MEM_CONTROLLER="1024"
  # We use haproxy in front of our controllers. 256MB is big for them.
  MEM_LB="256"

  # Slower
  K8S_BUNDLE_TAG="v1.12.0"
  ETCD_TAG="v3.3.9"
  K8S_HELM_TAG="v2.12.2"

  IP_K8S_CLUSTER="10.32.0.1"
  # The address of CoreDNS service which is deployed with `_k8s_bootstrapping_coredns`.
  # This address is used by `kubelet`  (etc/kubelet-config.yaml.in)
  # and also the deployment recipe (etc/coredns.yaml.in)
  IP_K8S_CLUSTER_COREDNS="10.32.0.10"
  IP_K8S_CLUSTER_RANGE="10.32.0.0/24"

  IP_K8S_KUBE_PROXY_RANGE="10.11.0.0/16"

  IP_K8S_POD_RANGE_PREFIX="10.200"
  IP_K8S_POD_RANGE="${IP_K8S_POD_RANGE_PREFIX}.0.0/16"
  # FIXME: Mission impossible. Below the value generated on Ubuntu system.
  # FIXME: There is no way to select and/or detect it.
  IP_DEV_NAME="enp0s8"

  MY_CLUSTER_NAME="hisk8s"

  IP_PREFIX="10.11.12"

  # Load balancer
  IP_LB="${IP_PREFIX}.100"
  LOAD_BALANCER="lb-100"

  CONTROLLER_START=110
  WORKER_START=140

  SSH_PORT_PREFIX="10"
  VBOX_PRIVATE_NETWORK_NAME="hisk8s"

  # General environments

  OHOME=$HOME
  D_ROOT="$(dirname "${BASH_SOURCE[0]:-}")/../"
  D_ROOT="$(cd "$D_ROOT" && pwd -P)"
  D_BIN="$D_ROOT/bin/"
  D_MACHINES="$D_ROOT/machines/"
  F_VAGRANTFILE="$D_BIN/Vagrantfile.rb"
  D_ETC="$D_ROOT/etc/"
  D_CA="$D_ROOT/ca/"
  D_CACHES="$D_ROOT/caches/"

  if [[ ! -f "$D_BIN/hisk8s.sh" ]]; then
    echo >&2 ":: hisk8s script not found in $D_BIN, or $D_ROOT/$D_BIN is invalid."
    return
  fi

  F_SSH_CONFIG="$D_ETC/ssh.config"
  F_SSH_KNOWN_HOSTS="$D_ETC/ssh.known_hosts"

  # Load custom environments

  if [[ -f "$D_ETC/custom.env.sh" ]]; then
    source "$D_ETC/custom.env.sh" || return
  else
    echo ":: Custom environment file not found: $D_ETC/custom.env.sh"
  fi

  n="$N_WORKERS"
  WORKERS=""
  while (( n )); do
    WORKERS="$WORKERS worker-$(( n + $WORKER_START ))"
    (( n -- ))
  done

  n="$N_CONTROLLERS"
  CONTROLLERS=""
  while (( n )); do
    CONTROLLERS="$CONTROLLERS controller-$(( n + $CONTROLLER_START ))"
    (( n -- ))
  done

  MACHINES="$LOAD_BALANCER $WORKERS $CONTROLLERS"

  # Internal methods
  _LAST_METHOD="unknown"
  _LAST_METHOD_RETURN_CODE="unknown"

  # See also https://github.com/kubernetes-sigs/cri-tools#current-status
  K8S_CRIT_TAG="${K8S_BUNDLE_TAG%.*}.0"

}

_ssh() { #public: ssh to any node. Use `_ssh_list` to list all nodes. Use '_ssh list' to list all aliases.
  if [[ "${@:-}" == "list" ]]; then
    _ssh_list
    return
  fi

  ssh -F "$F_SSH_CONFIG" "$@"
}

_ssh_worker() { #public: Execute command on all workers. E.g, `_ssh_worker hostname`
  for _node in $WORKERS; do
    echo >&2 ":: $_node: Executing '$@'"
    _ssh -n "$_node" "$@"
  done
}

_ssh_controller() { #public: Execute command on all controllers. E.g, `_ssh_worker hostname`
  for _node in $CONTROLLERS; do
    echo >&2 ":: $_node: Executing '$@'"
    _ssh -n "$_node" "$@"
  done
}

_rsync() { #public: A wrapper of `rsync` command, useful when you need to transfer file(s) to any node.
  rsync -e "ssh -F \"$F_SSH_CONFIG\"" "$@"
}

__export_env() {
  echo "set -a"
  env \
  | grep -Ee "^((K8S_)|(IP_))" \
  | while read -r _line; do
      echo "$_line";
    done
  while (( $# )); do
    _vname="$1"
    _vname="${_vname^^}"
    echo "${_vname}=${!_vname}"
    shift
  done
}

# Execute remote script
_execute_remote() {
  local _fn="$1"; shift
  if [[ "$_fn" == ":" ]]; then
    _fn="_remote"
  fi
  for _jnode in $*; do
    {
      __export_env
      declare -f $_fn;
      echo $_fn;
    } \
    | _ssh "$_jnode"
  done
}

_k8s_bootstrapping_lb() {
  ## dns stuff

  _remote() {
    echo Y | sudo pacman -S ruby ruby-dev build-essential
    echo "gem: --no-rdoc --no-ri -V" | sudo tee >/dev/null /etc/gemrc
    sudo gem install rubydns

    sudo systemctl daemon-reload
    sudo systemctl enable vboxdns
    sudo systemctl restart vboxdns
    sudo systemctl status vboxdns
  }

  _envsubst "$D_ETC/vboxdns.service.in" "$D_ETC/vboxdns.service" || return
  _rsync --rsync-path="sudo rsync" "$D_ETC/vboxdns.service" "$LOAD_BALANCER:"/etc/systemd/system/vboxdns.service
  _rsync -v "$D_BIN/dns_resolver.rb" $LOAD_BALANCER:~/

  _execute_remote : "$LOAD_BALANCER"

  ## haproxy

  _remote() {
    echo Y | sudo pacman -S haproxy
    sudo cp -fv haproxy.cfg /etc/haproxy/haproxy.cfg
    sudo systemctl enable haproxy
    sudo systemctl start haproxy
    sudo systemctl restart haproxy
    sudo systemctl status haproxy
    echo >&2 ":: haproxy available on your shell: http://localhost:1936/haproxy?stats#stats"
  }

  HAPROXY_K8S_APIS=""
  for _node in $CONTROLLERS; do
    HAPROXY_K8S_APIS="$HAPROXY_K8S_APIS\n    server $_node $IP_PREFIX.${_node#*-}:6443 check port 80"
  done

  # HAPROXY_K8S_WORKERS=""
  # for _node in $WORKERS; do
  #   HAPROXY_K8S_WORKERS="$HAPROXY_K8S_WORKERS\n    server $_node $IP_PREFIX.${_node#*-}:6443 check port 8080"
  # done

  _envsubst "$D_ETC/haproxy.cfg.in" "$D_ETC/haproxy.cfg" || return 1
  sed -i -e 's#\\n#\n#g' "$D_ETC/haproxy.cfg"
  _rsync "$D_ETC/haproxy.cfg" "$LOAD_BALANCER":~/haproxy.cfg

  _execute_remote : "$LOAD_BALANCER"
}

__k8s_kubelet_client_cert() {
  cd "$D_CA/" || return
  for _node in $WORKERS; do
    _node_fqdn="${_node}.internal"
    _envsubst "$D_ETC/ca/foo-csr.json.in" ${_node}-csr.json || return 1
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=${IP_LB},${_node},${_node_fqdn},"$IP_PREFIX.${_node#*-}" \
      -profile=kubernetes \
      ${_node}-csr.json | cfssljson -bare ${_node}
  done
}

_k8s_kubectl_config_distribute() {
  cd "$D_CA/" || return

  for _node in $WORKERS $CONTROLLERS; do
    if [[ "${_node:0:1}" == "w" ]]; then
      _files="${_node}.kubeconfig kube-proxy.kubeconfig"
    else
      _files="admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig"
    fi

    _rsync -va ${_files} ${_node}:~/
  done
}

_k8s_ca_distrubute() {
  cd "$D_CA/" || return
  for _node in $WORKERS $CONTROLLERS; do
    if [[ "${_node:0:1}" == "w" ]]; then
      _files="ca.pem ${_node}-key.pem ${_node}.pem"
    else
      _files="ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem"
    fi
    _rsync -va ${_files} ${_node}:~/
  done
}

_k8s_bootstrapping_ca() {
  mkdir -pv "$D_CA/"
  cp -fv "$D_ETC/ca/"*.* "$D_CA/"

  _k8s_ca_generate
  _k8s_ca_distrubute

  _k8s_kubectl_config_kubelet
  _k8s_kubectl_config_proxy
  _k8s_kubectl_config_controller_manager
  _k8s_kubectl_config_scheduler
  _k8s_kubectl_config_admin

  _k8s_kubectl_config_distribute
}

# for etcd cluster, see link: https://coreos.com/os/docs/latest/generate-self-signed-certificates.html
_ssl_generate() { #public: Generate self-sign ssl for a list of domains. Syntax: $0 first_domain optional_domains
  local _first_site="${1:-}"
  if [[ -z "${_first_site}" ]]; then
    echo >&2 ":: Missing the first site."
    return 1
  fi

  local _hosts=""
  while (( $# )); do
    _hosts="\"$1\",$_hosts"
    shift
  done
  _hosts="${_hosts%,*}"

  local _dsite="$D_CA/$_first_site"
  mkdir -pv "$_dsite"
  cd "$_dsite/" || return 1

  cp -fv "$D_ETC/ca/"/*.* ./
  # Generate ca-key.pem, ca.csr (not used), ca.pem
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca -

  SELF_SIGNED_CN_NAME="$_first_site"
  SELF_SIGNED_SSL_HOSTS="$_hosts"
  # cfssl print-defaults csr > server.json.in
  _envsubst "server.json.in" "server.json"

  # Output: server-key.pem server.csr (not user) server.pem
  # Configuration for nginx:
  #
  #   ssl_certificate     server.pem;
  #   ssl_certificate_key server-key.pem;
  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=server server.json \
  | cfssljson -bare server
}

_k8s_ca_generate() {
  cd "$D_CA/" || return

  # Output:
  # - ca-key.pem
  # - ca.csr (will not be used for website self-signed SSL)
  # - ca.pem
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    admin-csr.json | cfssljson -bare admin

  __k8s_kubelet_client_cert

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    kube-proxy-csr.json | cfssljson -bare kube-proxy

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    kube-scheduler-csr.json | cfssljson -bare kube-scheduler

  n=$N_CONTROLLERS
  tmp=""
  while (( n )); do
    tmp="$tmp,${IP_PREFIX}.$(( n + CONTROLLER_START))"
    (( n-- ))
  done

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname=${IP_K8S_CLUSTER},${IP_LB}${tmp},127.0.0.1,kubernetes.default \
    -profile=kubernetes \
    kubernetes-csr.json | cfssljson -bare kubernetes

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    service-account-csr.json | cfssljson -bare service-account
}

_k8s_kubectl_config_proxy() {
  cd "$D_CA/" || return

  kubectl config set-cluster ${MY_CLUSTER_NAME} \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${IP_LB}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=${MY_CLUSTER_NAME} \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}

_k8s_kubectl_config_scheduler() {
  cd "$D_CA/" || return

  kubectl config set-cluster ${MY_CLUSTER_NAME} \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server="https://127.0.0.1:6443" \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem \
    --client-key=kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=${MY_CLUSTER_NAME} \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}

_k8s_kubectl_config_admin() {
  cd "$D_CA/" || return

  kubectl config set-cluster ${MY_CLUSTER_NAME} \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=${MY_CLUSTER_NAME} \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

_k8s_kubectl_config_controller_manager() {
  cd "$D_CA/" || return

  kubectl config set-cluster ${MY_CLUSTER_NAME} \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem \
    --client-key=kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=${MY_CLUSTER_NAME} \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}

_k8s_kubectl_config_kubelet() {
  cd "$D_CA/" || return

  for _node in $WORKERS; do
    kubectl config set-cluster ${MY_CLUSTER_NAME} \
      --certificate-authority=ca.pem \
      --embed-certs=true \
      --server=https://${IP_LB}:6443 \
      --kubeconfig=${_node}.kubeconfig

    kubectl config set-credentials system:node:${_node} \
      --client-certificate=${_node}.pem \
      --client-key=${_node}-key.pem \
      --embed-certs=true \
      --kubeconfig=${_node}.kubeconfig

    kubectl config set-context default \
      --cluster=${MY_CLUSTER_NAME} \
      --user=system:node:${_node} \
      --kubeconfig=${_node}.kubeconfig

    kubectl config use-context default --kubeconfig=${_node}.kubeconfig
  done
}

_wget_etcd() {
  mkdir -pv "$D_CACHES/etcd/"
  cd "$D_CACHES/etcd/" || return
  __wget "https://github.com/coreos/etcd/releases/download/${ETCD_TAG}/etcd-${ETCD_TAG}-linux-amd64.tar.gz"
}

# Requirement: _k8s_bootstrapping_lb
_k8s_bootstrapping_etcd() {
  _remote() {
    tar -xvf etcd-${ETCD_TAG}-linux-amd64.tar.gz
    sudo mv etcd-${ETCD_TAG}-linux-amd64/etcd* /usr/local/bin/

    sudo systemctl stop etcd
    sudo rm -rfv /var/lib/etcd/
    sudo mkdir -p /etc/etcd /var/lib/etcd

    sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

    sudo systemctl daemon-reload
    sudo systemctl enable etcd
    sudo systemctl start etcd
    sudo systemctl status etcd
  }

  _wget_etcd

  for _node in $CONTROLLERS; do
    echo "::"
    echo ":: Bootstrapping etcd on $_node"

    _rsync -rav "$D_CACHES/etcd/" "$_node":~/
    ETCD_NAME="$_node"
    INTERNAL_IP="${IP_PREFIX}.${ETCD_NAME#*-}"

    ETC_NODES=""
    for _jnode in $CONTROLLERS; do
      ETC_NODES="$_jnode=https://${IP_PREFIX}.${_jnode#*-}:2380,$ETC_NODES"
    done

    ETC_NODES="${ETC_NODES%,*}" # remove the last ,
    _envsubst "$D_ETC/etcd.service.in" "$D_ETC/$_node.etcd.service" || return 1
    _rsync --rsync-path="sudo rsync" -av "$D_ETC/$_node.etcd.service" "$_node":/etc/systemd/system/etcd.service
    _execute_remote : $_node
    echo ":: Bootstrapping etcd on $_node [complete]"
    echo "::"
  done
}

_k8s_encryption_key_gen() {
  F_CONFIG="$D_ETC/encryption-config.yaml"

  if [[ ! -f "$F_CONFIG" ]]; then
    ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
    _envsubst "$F_CONFIG.in" "$F_CONFIG" || return 1
  else
    echo >&2 ":: File $F_CONFIG does exist. Skip updating."
  fi

  for _node in $CONTROLLERS; do
    _rsync -av "$F_CONFIG" "$_node":~/
  done
}

_k8s_bootstrapping_control_plane() {
  _remote() {
    sudo chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
    sudo cp -ufv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

    sudo mkdir -pv /var/lib/kubernetes/ /etc/kubernetes/config/

    sudo cp -ufv \
      ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
      service-account-key.pem service-account.pem \
      encryption-config.yaml /var/lib/kubernetes/

    sudo cp -ufv ~/kube-controller-manager.kubeconfig /var/lib/kubernetes/
    sudo cp -ufv ~/kube-scheduler.kubeconfig /var/lib/kubernetes/
    sudo cp -ufv ~/kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml

    sudo systemctl daemon-reload
    for _service in kube-apiserver kube-controller-manager kube-scheduler; do
      sudo systemctl enable  $_service;
      sudo systemctl restart $_service;
    done

    echo Y | sudo DEBIAN_FRONTEND=noninteractive pacman -S nginx
    sudo rm -fv /etc/nginx/sites-enabled/default
    sudo cp -ufv ~/nginx_k8s_healthcheck.conf /etc/nginx/sites-enabled/

    sudo systemctl enable nginx
    sudo systemctl restart nginx
  }

  _wget_control_plane

  for _node in $CONTROLLERS; do
    echo "::"
    echo ":: Bootstrapping control plane on $_node"

    _rsync -rav "$D_CACHES/controller/" "$_node":~/

    ETCD_NODES=""
    for _jnode in $CONTROLLERS; do
      ETCD_NODES="https://${IP_PREFIX}.${_jnode#*-}:2379,$ETCD_NODES"
    done

    ETCD_NODES="${ETCD_NODES%,*}" # remove the last ,
    IP_KUBE_API_SERVER_ADVERTISE="${IP_PREFIX}.${_node#*-}"

    _envsubst "$D_ETC/kube-apiserver.service.in"  "$D_ETC/kube-apiserver.service" || return 1
    _envsubst "$D_ETC/kube-controller-manager.service.in" "$D_ETC/kube-controller-manager.service" || return 1

    _rsync --rsync-path="sudo rsync" $D_ETC/kube-scheduler.service  $_node:/etc/systemd/system/kube-scheduler.service
    _rsync --rsync-path="sudo rsync" $D_ETC/kube-controller-manager.service  $_node:/etc/systemd/system/kube-controller-manager.service
    _rsync --rsync-path="sudo rsync" $D_ETC/kube-apiserver.service  $_node:/etc/systemd/system/kube-apiserver.service

    _rsync $D_ETC/kube-scheduler.yaml     $_node:~/
    _rsync $D_ETC/nginx_k8s_healthcheck.conf $_node:~/

    _execute_remote : $_node

    echo ":: Bootstrapping control plane on $_node [compelete]"
    echo "::"
  done
}

_wget_control_plane() {
  mkdir -pv "$D_CACHES/controller/"
  cd "$D_CACHES/controller/" || return
  __wget \
    "https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kube-apiserver" \
    "https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kube-controller-manager" \
    "https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kube-scheduler" \
    "https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kubectl"
}

_k8s_bootstrapping_rbac_cluster_role() {
  for _file in kube-rbac-ClusterRole.yaml kube-rbac-ClusterRoleBinding.yaml ; do
    for _node in $CONTROLLERS; do
      echo >&2 ":: Applying $_file on $_node"
      < "$D_ETC/$_file" _ssh "$_node" kubectl apply --kubeconfig admin.kubeconfig -f -
    done
  done
}

_k8s_worker_routing() {
  for _node in $WORKERS; do
  echo >&2 ":: Routing tables on $_node"
  _current_idx="${_node#*-}"
  _routes="true"
  n=$N_WORKERS
  while (( n )); do
    _n_index=$(( n + WORKER_START ))
    if [[ "$_n_index" != "$_current_idx" ]]; then
      POD_CIDR="${IP_K8S_POD_RANGE_PREFIX}.${_n_index}.0/24"
      _routes="$_routes; sudo route add -net $POD_CIDR gw ${IP_PREFIX}.$_n_index dev ${IP_DEV_NAME}"
    fi

    (( n-- ))
  done

  _ssh -n "$_node" "$_routes; sudo route -n"
done

}

_wget_worker() {
  mkdir -pv "$D_CACHES/worker/"
  cd "$D_CACHES/worker/" || return
  __wget \
    https://github.com/kubernetes-sigs/cri-tools/releases/download/${K8S_CRIT_TAG}/crictl-${K8S_CRIT_TAG}-linux-amd64.tar.gz \
    https://storage.googleapis.com/kubernetes-the-hard-way/runsc-50c283b9f56bb7200938d9e207355f05f79f0d17 \
    https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64 \
    https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
    https://github.com/containerd/containerd/releases/download/v1.2.0-rc.0/containerd-1.2.0-rc.0.linux-amd64.tar.gz \
    https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kubectl \
    https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kube-proxy \
    https://storage.googleapis.com/kubernetes-release/release/${K8S_BUNDLE_TAG}/bin/linux/amd64/kubelet
}

_k8s_bootstrapping_worker() {
  _remote() {

    sudo pacman -Sy
    # socat is required by kubectl port-forward
    echo Y | sudo pacman -S socat conntrack ipset

    sudo mkdir -p \
      /opt/cni/bin \
      /var/lib/kubelet \
      /var/lib/kube-proxy \
      /var/lib/kubernetes \
      /var/run/kubernetes

    # Install the worker binaries:
    sudo cp -fuv runsc-50c283b9f56bb7200938d9e207355f05f79f0d17 runsc
    sudo cp -fuv runc.amd64 runc
    sudo chmod +x kubectl kube-proxy kubelet runc runsc
    sudo cp -fuv kubectl kube-proxy kubelet runc runsc /usr/local/bin/
    sudo tar -xvf crictl-${K8S_CRIT_TAG}-linux-amd64.tar.gz -C /usr/local/bin/
    sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/
    sudo tar -xvf containerd-1.2.0-rc.0.linux-amd64.tar.gz -C /

    sudo mkdir -pv /etc/cni/net.d/
    sudo cp -fuv ${HOSTNAME}.10-bridge.conf   /etc/cni/net.d/10-bridge.conf
    sudo cp -fuv 99-loopback.conf             /etc/cni/net.d/99-loopback.conf

    sudo mkdir -p /etc/containerd/

    sudo cp -fuv ${HOSTNAME}-key.pem ${HOSTNAME}.pem /var/lib/kubelet/
    sudo cp -fuv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
    sudo cp -fuv ca.pem /var/lib/kubernetes/

    sudo cp -fvu containerd.config.toml /etc/containerd/config.toml
    sudo cp -fuv containerd.service /etc/systemd/system/containerd.service
    sudo cp -fuv ${HOSTNAME}.kubelet-config.yaml /var/lib/kubelet/kubelet-config.yaml
    sudo cp -fuv kubelet.service /etc/systemd/system/kubelet.service
    sudo cp -fuv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
    sudo cp -fuv kube-proxy-config.yaml /var/lib/kube-proxy/kube-proxy-config.yaml
    sudo cp -fuv ${HOSTNAME}.kube-proxy.service  /etc/systemd/system/kube-proxy.service

    sudo systemctl daemon-reload
    sudo systemctl enable containerd kubelet kube-proxy
    sudo systemctl restart containerd kubelet kube-proxy
  }

  _wget_worker

  for _node in $WORKERS; do
    echo "::"
    echo ":: Bootstrapping worker $_node"
    IP_POD_RANGE="${IP_K8S_POD_RANGE_PREFIX}.${_node#*-}.0/24"
    IP_NODEPORT_RANGES="${IP_PREFIX}.${_node#*-}/32"

    _envsubst "$D_ETC/kube-proxy.service.in"          "$D_ETC/$_node.kube-proxy.service"
    _envsubst "$D_ETC/10-bridge.conf.in"          "$D_ETC/$_node.10-bridge.conf"
    _envsubst "$D_ETC/kube-proxy-config.yaml.in"     "$D_ETC/kube-proxy-config.yaml"
    _envsubst "$D_ETC/kubelet-config.yaml.in"     "$D_ETC/$_node.kubelet-config.yaml"

    _rsync -rapv "$D_CACHES/worker/" $_node:~/
    _rsync -av \
      "$D_ETC/containerd.config.toml" \
      "$D_ETC/containerd.service" \
      "$D_ETC/${_node}.kubelet-config.yaml" \
      "$D_ETC/kubelet.service" \
      "$D_ETC/kube-proxy-config.yaml" \
      "$D_ETC/${_node}.10-bridge.conf" \
      "$D_ETC/99-loopback.conf" \
      "$D_ETC/$_node.kube-proxy.service" \
      $_node:~/

    _execute_remote : "$_node"

    echo ":: Bootstrapping worker $_node [complete]"
    echo "::"
  done
}

_envsubst() {
  echo ":: Creating file $2 from $1"
  echo "$2" >> "$D_ETC/envsubst.list"
  envsubst < "$1" > "$2"
  if grep -sqE '\${.+}' "$2"; then
    return 1
  else
    return 0
  fi
}

_k8s_bootstrapping_coredns() {
  # F_YAML="https://storage.googleapis.com/kubernetes-the-hard-way/coredns.yaml"
  # Downloaded -> etc/coredns.yaml.in
  _envsubst "$D_ETC/coredns.yaml"{.in,} || return
  _kubectl apply -f "$D_ETC/coredns.yaml"
}

_k8s_bootstrapping_kubectl_config() {
  cd "$D_ROOT/ca/" || return

  HOME="$D_ETC/"

  KUBERNETES_PUBLIC_ADDRESS="127.0.0.1"

  kubectl config set-cluster ${MY_CLUSTER_NAME} \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem

  kubectl config set-context ${MY_CLUSTER_NAME} \
    --cluster=${MY_CLUSTER_NAME} \
    --user=admin

  kubectl config use-context ${MY_CLUSTER_NAME}
}

_smoke_tests() { #public: Run some simple smoke tests against new cluster
  _smoke_test_lb
  _smoke_test_etcd
  _smoke_test_control_plane
}

_smoke_test_deploy_app() {
  _kubectl create secret generic $MY_CLUSTER_NAME --from-literal="mykey=mydata"
  for _node in $CONTROLLERS; do
    _ssh -n $_node \
      "sudo ETCDCTL_API=3 etcdctl get \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/etcd/ca.pem \
      --cert=/etc/etcd/kubernetes.pem \
      --key=/etc/etcd/kubernetes-key.pem\
      /registry/secrets/default/$MY_CLUSTER_NAME | hexdump -C" \

    break
  done

  _kubectl run nginx --image=nginx
  _kubectl run busybox --image=busybox:1.28 --command -- sleep 86400

  _kubectl get Pods -o wide --all-namespaces
  _kubectl get componentstatuses

  POD_NAME=$(_kubectl get pods -l run=busybox -o jsonpath="{.items[0].metadata.name}")
  _kubectl exec -ti $POD_NAME -- nslookup kubernetes
}

_smoke_test_control_plane() {
  for _node in $CONTROLLERS; do
    echo >&2 "::"
    echo >&2 ":: Verifying with healthcheck on each $_node"
    _ssh -n "$_node" "
      for _service in kube-apiserver kube-controller-manager kube-scheduler; do
        sudo systemctl status \$_service | grep -m 3 -i erro[r]
      done
    "
  done

  echo 2>&1 "Components"
  # FIXME: can't use with --kubeconfig "$D_CA/admin.kubeconfig"
  # FIXME: because the context is different.
  _kubectl get componentstatuses
  curl -s -H \"Host: kubernetes.default.svc.cluster.local\" -i http://127.0.0.1/healthz >/dev/null
}

_kubectl() { #public: A wrapper of kubectl. E.g., `_kubectl get pods --all-namespaces`
  HOME="$D_ETC/"
  kubectl --context="$MY_CLUSTER_NAME" "$@"
}

_smoke_test_etcd() { #public: Simple smoke tests against etcd setup.
  for _node in $CONTROLLERS; do
    echo ":: etcd connective on $_node"

    _ssh -n $_node \
      sudo ETCDCTL_API=3 etcdctl member list \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem
  done
}

_smoke_test_lb() { #public: Simple smoke tests against custom DNS and Load balancer.
  echo >&2 ":: Testing from your laptop : Accessing k8s api"
  curl \
    -s --resolve "kubernetes.default:6443:127.0.0.1" \
    --cacert "$D_CA/ca.pem"  \
    "https://kubernetes.default:6443/version"
  echo

  _ssh -n $LOAD_BALANCER "
    echo >&2 ':: Testing inside LB instance : Accessing k8s api'
    curl -s -k https://localhost:6443/version
    echo
    echo >&2 ':: Testing dns resolver'
    for _node in ${MACHINES} k8s random$RANDOM.k8s; do
      echo \"Resolving \$_node : \$(dig @localhost A +short \$_node | head -1)\"
    done
  "

  echo >&2 ":: Haproxy stats: http://localhost:1936/haproxy?stats (user: admin password: admin)"
}

_wget_helm() { #public: Download helm binary to $D_CACHES/ directory
  mkdir -pv "$D_CACHES/"
  cd "$D_CACHES/" || return
  __wget https://storage.googleapis.com/kubernetes-helm/helm-"${K8S_HELM_TAG}"-linux-amd64.tar.gz
  tar xfvz helm-"${K8S_HELM_TAG}"-linux-amd64.tar.gz linux-amd64/helm
  mv linux-amd64/helm "./helm-${K8S_HELM_TAG}"
  ls -la helm-*
}

_wget_kubectl() { #public: Download kubectl binary to $D_CACHES/ directory.
  mkdir -pv "$D_CACHES/"
  cd "$D_CACHES/" || return
  __wget -O kubectl-"${K8S_BUNDLE_TAG}" https://storage.googleapis.com/kubernetes-release/release/"$K8S_BUNDLE_TAG}"/bin/darwin/amd64/kubectl
  ls -la kubectl-*
}

__wget() {
  echo >&2 ":: Downloading:"
  for _uri in $*; do
    echo >&2 "   - $_uri"
  done

  wget -c -q --https-only --show-progress --timestamping "$@"
}

_remote_install_kubectl() {
  export DEBIAN_FRONTEND=noninteractive

  cd ~/
  curl -Lso get.docker.com{.sh,}
  bash -x get.docker.com.sh

  sudo pacman -Sy
  echo Y | sudo pacman -S apt-transport-https
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
  echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
  sudo pacman -Sy
  echo Y | sudo pacman -S kubectl
}

_helm() { #public: A wrapper of helm command
  HOME="$D_ETC/"
  helm "$@"
}

# The plugin is loaded by default...
# _helm_init_plugin_diff() { #public: Install diff plugin for helm
#   HOME="$D_ETC/"
#   helm plugin install https://github.com/databus23/helm-diff --version master
# }

_helm_init() { #public: Install and patch `helm` settings.
  HOME="$D_ETC/"
  helm init
  kubectl create serviceaccount --namespace kube-system tiller
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
  kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
}

_test() { #public: Default test (See README#getting-started). Create new cluster and test.
  set -xe
  __execute __require
  __execute _vagrant up
  __execute _k8s_bootstrapping_ca
  __execute _k8s_bootstrapping_lb
  __execute _k8s_bootstrapping_etcd
  __execute _k8s_encryption_key_gen
  __execute _k8s_bootstrapping_control_plane
  __execute _k8s_bootstrapping_rbac_cluster_role
  __execute _k8s_bootstrapping_worker
  __execute _k8s_worker_routing
  __execute _k8s_bootstrapping_kubectl_config
  __execute _k8s_bootstrapping_coredns
}

__execute() {
  local _method="${1:-}"
  if [[ -z "${_method}" ]]; then
    echo >&2 ":: Missing method name."
    return 1
  fi

  _LAST_METHOD_RETURN_CODE="unknown"
  _LAST_METHOD="$_method"
  echo >&2 ":: Executing $_LAST_METHOD"

  "$@"
  _LAST_METHOD_RETURN_CODE="$?"

  echo >&2 ":: Complete $_LAST_METHOD, Return code: $_LAST_METHOD_RETURN_CODE"
  return "$_LAST_METHOD_RETURN_CODE"
}

__require() {
  local _commons="
    kubectl \
    cfssl \
    envsubst \
    vagrant \
    wget \
    rsync \
    curl \
    column \
    sort \
    sed \
    tar \
  "
  for _c in ${*:-$_commons}; do
    command -V "$_c" > /dev/null || return
  done
}

__trap() {
  set +x

  if [[ "${_LAST_METHOD:-unknown}" != "unknown" ]]; then
    echo >&2 ":: =========================="
    echo >&2 ":: Last method: $_LAST_METHOD"
    echo >&2 ":: Last method return code: $_LAST_METHOD_RETURN_CODE"
  fi
}

_env() { #public: Show hisk8s environments
  local _sig="☠"
  cat <<EOF | column -s"$_sig" -t
Environments:
  Directory:
    Root:           $_sig$D_ROOT
    Configuration:  $_sig$D_ETC
    Caching:        $_sig$D_CACHES
    Certificates:   $_sig$D_CA
  Hisk8s:
    Version:        ${_sig}0.0.0-alpha

Cluster:
  Number of workers:      $_sig$N_WORKERS (memory: $MEM_WORKER)
  Number of controllers:  $_sig$N_CONTROLLERS (memory: $MEM_CONTROLLER)
  Node IP prefix:         $_sig$IP_PREFIX
  Load balancer:          $_sig$IP_LB (memory: $MEM_LB)
  Vagrant local data:     $_sig$D_ROOT/machines/

Kubernetes:
  Bundle version:       $_sig$K8S_BUNDLE_TAG
  Helm version:         $_sig$K8S_HELM_TAG
  Kube configuration:   $_sig$D_ETC/.kube/config
  Kubectl wrapper:      $_sig$D_BIN/_kubectl
EOF
}

_me_list_public_methods() {
  LANG=en_US.UTF_8
  grep -E '^_.+ #public' "$0" | sed -e 's|() { #public: |☠|g' | column -s"☠" -t | sort
}

trap  __trap EXIT

# Basic support
_basename="$(basename "$0")"
case "$_basename" in
"_kubectl"|"_helm"|"_ssh"|"_env")
  _command="$_basename"
  env_setup || exit
  $_command "$@"
  exit
  ;;
esac

case "${1:-}" in
""|"-h"|"--help") _me_list_public_methods; exit ;;
esac

env_setup
"$@"
