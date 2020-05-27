#!/usr/bin/env bash

set -o pipefail
set -o nounset
#set -o errexit
IFS=$'\n\t'

TEMPLATE_DIR="${TEMPLATE_DIR:-./files}"

export BINARY_BUCKET_NAME="amazon-eks"
export BINARY_BUCKET_REGION="us-west-2"
export AWS_ACCESS_KEY_ID=""
export KUBERNETES_BUILD_DATE="2020-04-16"
export CNI_VERSION="v0.6.0"
export CNI_PLUGIN_VERSION="v0.8.5"
export KUBERNETES_VERSION="1.16.8"

export PATH="/usr/local/bin:$PATH"

MACHINE=$(uname -m)
if [ "$MACHINE" == "x86_64" ]; then
    ARCH="amd64"
    OS="linux"
elif [ "$MACHINE" == "aarch64" ]; then
    ARCH="arm64"
else
    echo "Unknown machine architecture '$MACHINE'" >&2
    exit 1
fi

if grep --quiet tsc /sys/devices/system/clocksource/clocksource0/available_clocksource; then
    echo "tsc" | sudo tee /sys/devices/system/clocksource/clocksource0/current_clocksource
else
    echo "tsc as a clock source is not applicable, skipping."
fi

sudo yum update -y
sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 
sudo yum install -y \
    git \
    zip \
    unzip \
    wget \
    curl \
    python3-pip \
    chrony \
    conntrack \
    curl \
    nfs-utils \
    socat    

sudo chkconfig chronyd on

cat <<EOF | sudo tee -a /etc/chrony.conf
rtcsync
EOF

sudo pip3 install --upgrade \
    pip \
    awscli \
    jq \
    pystache \
    argparse \
    python-daemon \
    requests

sudo sed -i 's/enforcing/permissive/g' /etc/selinux/config 

sudo bash -c "/sbin/iptables-save > /etc/sysconfig/iptables"

sudo cp -r "${TEMPLATE_DIR}"/iptables-restore.service /etc/systemd/system/iptables-restore.service

sudo systemctl daemon-reload
sudo systemctl enable iptables-restore ## FAILS

# Install and Configure CFN
wget https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz 
sudo tar -xzvf aws-cfn-bootstrap-latest.tar.gz -C /opt
pushd /opt/aws-cfn-bootstrap-1.4/
    sudo python setup.py build
    sudo python setup.py install
popd
sudo ln -s /usr/init/redhat/cfn-hup /etc/init.d/cfn-hup
sudo chmod 775 /usr/init/redhat/cfn-hup
sudo mkdir -p /opt/aws/bin
sudo ln -s /usr/bin/cfn-hup /opt/aws/bin/cfn-hup
sudo ln -s /usr/bin/cfn-signal /opt/aws/bin/cfn-signal

INSTALL_DOCKER="${INSTALL_DOCKER:-true}"
if [[ "$INSTALL_DOCKER" == "true" ]]; then
    # Install required packages.
    sudo yum install -y yum-utils \
    device-mapper-persistent-data \
    lvm2

    # Install container-selinux.
    sudo yum install -y \
    http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-3.el7.noarch.rpm

    # Set up Docker repository.
    sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker CE and tools.
    sudo yum install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io

    sudo mkdir -p /etc/docker
    sudo cp -r "${TEMPLATE_DIR}"/docker-daemon.json /etc/docker/daemon.json
    sudo chown root:root /etc/docker/daemon.json

    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo chkconfig docker on
    sudo usermod -aG docker "${USER}"
fi

sudo cp -r "${TEMPLATE_DIR}"/logrotate-kube-proxy /etc/logrotate.d/kube-proxy
sudo chown root:root /etc/logrotate.d/kube-proxy
sudo mkdir -p /var/log/journal

sudo mkdir -p /etc/kubernetes/manifests
sudo mkdir -p /var/lib/kubernetes
sudo mkdir -p /var/lib/kubelet
sudo mkdir -p /opt/cni/bin

wget https://github.com/containernetworking/cni/releases/download/${CNI_VERSION}/cni-${ARCH}-${CNI_VERSION}.tgz
wget https://github.com/containernetworking/cni/releases/download/${CNI_VERSION}/cni-${ARCH}-${CNI_VERSION}.tgz.sha512
sudo sha512sum -c cni-${ARCH}-${CNI_VERSION}.tgz.sha512
sudo tar -xzvf cni-${ARCH}-${CNI_VERSION}.tgz -C /opt/cni/bin
sudo rm cni-${ARCH}-${CNI_VERSION}.tgz cni-${ARCH}-${CNI_VERSION}.tgz.sha512
 
wget https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-${OS}-${ARCH}-${CNI_PLUGIN_VERSION}.tgz
wget https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-${OS}-${ARCH}-${CNI_PLUGIN_VERSION}.tgz.sha512
sudo sha512sum -c cni-plugins-${OS}-${ARCH}-${CNI_PLUGIN_VERSION}.tgz.sha512
sudo tar -xzvf cni-plugins-${OS}-${ARCH}-${CNI_PLUGIN_VERSION}.tgz -C /opt/cni/bin
sudo rm cni-plugins-${OS}-${ARCH}-${CNI_PLUGIN_VERSION}.tgz cni-plugins-${OS}-${ARCH}-${CNI_PLUGIN_VERSION}.tgz.sha512 ## FAIL

echo "Downloading binaries from: s3://$BINARY_BUCKET_NAME"
S3_DOMAIN="s3-$BINARY_BUCKET_REGION"
if [ "$BINARY_BUCKET_REGION" = "us-east-1" ]; then
    S3_DOMAIN="s3"
fi
S3_URL_BASE="https://$S3_DOMAIN.amazonaws.com/$BINARY_BUCKET_NAME/$KUBERNETES_VERSION/$KUBERNETES_BUILD_DATE/bin/linux/$ARCH"
S3_PATH="s3://$BINARY_BUCKET_NAME/$KUBERNETES_VERSION/$KUBERNETES_BUILD_DATE/bin/linux/$ARCH"

BINARIES=(
    kubelet
    kubectl
    aws-iam-authenticator
)
for binary in ${BINARIES[*]} ; do
    if [[ ! -z "${AWS_ACCESS_KEY_ID}" ]]; then
        echo "AWS cli present - using it to copy binaries from s3."
        aws s3 cp --region $BINARY_BUCKET_REGION $S3_PATH/$binary .
        aws s3 cp --region $BINARY_BUCKET_REGION $S3_PATH/$binary.sha256 .
    else
        echo "AWS cli missing - using wget to fetch binaries from s3. Note: This won't work for private bucket."
        sudo wget $S3_URL_BASE/$binary
        sudo wget $S3_URL_BASE/$binary.sha256
    fi
    sudo sha256sum -c $binary.sha256
    sudo chmod +x $binary
    sudo mv $binary /usr/bin/
done
sudo rm *.sha256

KUBELET_CONFIG=""
KUBERNETES_MINOR_VERSION=${KUBERNETES_VERSION%.*}
if [ "$KUBERNETES_MINOR_VERSION" = "1.10" ] || [ "$KUBERNETES_MINOR_VERSION" = "1.11" ]; then
    KUBELET_CONFIG=kubelet-config.json
else
    KUBELET_CONFIG=kubelet-config-with-secret-polling.json
fi

sudo mkdir -p /etc/kubernetes/kubelet
sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo cp -r "${TEMPLATE_DIR}"/kubelet-kubeconfig /var/lib/kubelet/kubeconfig
sudo chown root:root /var/lib/kubelet/kubeconfig
sudo cp -r "${TEMPLATE_DIR}"/kubelet.service /etc/systemd/system/kubelet.service
sudo chown root:root /etc/systemd/system/kubelet.service
sudo cp -r "${TEMPLATE_DIR}"/$KUBELET_CONFIG /etc/kubernetes/kubelet/kubelet-config.json
sudo chown root:root /etc/kubernetes/kubelet/kubelet-config.json

sudo systemctl daemon-reload
sudo systemctl disable kubelet

sudo mkdir -p /etc/eks
sudo cp -r "${TEMPLATE_DIR}"/eni-max-pods.txt /etc/eks/eni-max-pods.txt
sudo cp -r "${TEMPLATE_DIR}"/bootstrap.sh /etc/eks/bootstrap.sh
sudo chmod +x /etc/eks/bootstrap.sh

BASE_AMI_ID=$(curl -s  http://169.254.169.254/latest/meta-data/ami-id)
cat <<EOF > /tmp/release
BASE_AMI_ID="$BASE_AMI_ID"
BUILD_TIME="$(date)"
BUILD_KERNEL="$(uname -r)"
ARCH="$(uname -m)"
EOF
sudo mv /tmp/release /etc/eks/release
sudo chown root:root /etc/eks/*

sudo yum clean all
sudo rm -rf /var/cache/yum

sudo touch /etc/machine-id
