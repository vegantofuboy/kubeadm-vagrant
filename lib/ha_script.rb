
require_relative 'vars'
require_relative 'helpers'

$ha_script = <<SCRIPT
#!/bin/bash

set -eo pipefail

status() {
    echo -e "\033[35m >>>   $*\033[0;39m"
}

status "configuring haproxy and keepalived.."
apt-get install -y keepalived haproxy

systemctl stop keepalived || true

vrrp_if=$(ip a | grep 192.168.26 | awk '{print $7}')
vrrp_ip=$(ip a | grep 192.168.26 | awk '{split($2, a, "/"); print a[1]}')
vrrp_state="BACKUP"
vrrp_priority="100"
if [ "${vrrp_ip}" = "#{$NODE_IP_NW}11" ]; then
  vrrp_state="MASTER"
  vrrp_priority="101"
fi

cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id LVS_DEVEL
}
vrrp_script check_apiserver {
    script "/etc/keepalived/check_apiserver.sh"
    interval 2
    weight -5
    fall 3
    rise 2
}
vrrp_instance VI_1 {
    state ${vrrp_state}
    interface ${vrrp_if}
    mcast_src_ip ${vrrp_ip}
    virtual_router_id 51
    priority ${vrrp_priority}
    advert_int 2
    authentication {
        auth_type PASS
        auth_pass a6E/CHhJkCn1Ww1gF3qPiJTKTEc=
    }
    virtual_ipaddress {
        #{$MASTER_IP}
    }
    track_script {
       check_apiserver
    }
}
EOF

cat > /etc/keepalived/check_apiserver.sh <<EOF
#!/bin/bash

errorExit() {
  echo "*** $*" 1>&2
  exit 1
}

curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:6443/"
if ip addr | grep -q #{$MASTER_IP}; then
  curl --silent --max-time 2 --insecure https://#{$MASTER_IP}:#{$MASTER_PORT}/ -o /dev/null || errorExit "Error GET https://#{$MASTER_IP}:#{$MASTER_PORT}/"
fi
EOF

systemctl restart keepalived
sleep 10

cat > /etc/haproxy/haproxy.cfg <<EOF
global
  log /dev/log  local0
  log /dev/log  local1 notice
  chroot /var/lib/haproxy
  user haproxy
  group haproxy
  daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client 50s
    timeout client-fin 50s
    timeout server 50s
    timeout tunnel 1h

listen stats
    bind *:1080
    stats refresh 30s
    stats uri /stats

listen kube-api-server
    bind #{$MASTER_IP}:#{$MASTER_PORT}
    mode tcp
    option tcplog
    balance roundrobin

#{gen_haproxy_backend($MASTER_COUNT)}
EOF

systemctl restart haproxy

if [ ${vrrp_state} = "MASTER" ]; then
  cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta1
kind: InitConfiguration
bootstrapTokens:
- token: #{$KUBE_TOKEN}
  ttl: 24h
localAPIEndpoint:
  advertiseAddress: ${vrrp_ip}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v#{$KUBE_VER}
controlPlaneEndpoint: "#{$MASTER_IP}:#{$MASTER_PORT}"
imageRepository: #{$IMAGE_REPO}
networking:
  podSubnet: 10.244.0.0/16
EOF

  status "running kubeadm init on the first master node.."
  kubeadm reset -f
  kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs | tee /vagrant/kubeadm.log

  mkdir -p $HOME/.kube
  sudo cp -Rf /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
  
  status "installing flannel network addon.."
  kubectl apply -f /vagrant/kube-flannel.yml
else
  status "joining master node.."
  discovery_token_ca_cert_hash="$(grep 'discovery-token-ca-cert-hash' /vagrant/kubeadm.log | head -n1 | awk '{print $2}')"
  certificate_key="$(grep 'certificate-key' /vagrant/kubeadm.log | head -n1 | awk '{print $3}')"
  kubeadm reset -f
  kubeadm join #{$MASTER_IP}:#{$MASTER_PORT} --token #{$KUBE_TOKEN} \
    --discovery-token-ca-cert-hash ${discovery_token_ca_cert_hash} \
    --experimental-control-plane --certificate-key ${certificate_key} \
    --apiserver-advertise-address ${vrrp_ip}
fi
SCRIPT