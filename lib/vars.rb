$BOX_IMAGE    = "ubuntu/disco64"
$MASTER_COUNT = 1
$NODE_COUNT   = 2
$MASTER_IP    = "192.168.26.10"
$MASTER_PORT  = "8443"
$NODE_IP_NW   = "192.168.26."
$POD_NW_CIDR  = "10.244.0.0/16"
               
$DOCKER_VER = "5:19.03.5~3-0~ubuntu-bionic"
$KUBE_VER   = "1.17.0"
$KUBE_TOKEN = "ayngk7.m1555duk5x2i3ctt"
$IMAGE_REPO = "k8s.gcr.io" # "registry.aliyuncs.com/google_containers"

$PUBLIC_LOAD_BALANCER_COUNT = 2
$PUBLIC_LOAD_BALANCER_IP_NW = "192.168.10."
$PUBLIC_LOAD_BALANCER_IP    = "192.168.10.10"