#!/bin/bash

# simple script to install docker, k8s, flannel on Ubuntu 20.04
# assumes a new Ubuntu20.04 install - use at your own risk

ufw disable
swapoff -a      # you may also need to edit /etc/fstab to remove swap entries
apt update
apt upgrade

apt install docker.io
systemctl start docker && systemctl enable docker

apt install apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt install kubeadm kubelet kubectl kubernetes-cni
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

apt install flannel