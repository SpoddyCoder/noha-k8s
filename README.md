# `noha-k8s` - low cost kubernetes ingress without a load balancer

`noha-k8s` outlines an anti-pattern to deploy a kubernetes cluster on any host / cloud provider (AWS, Azure, GCP etc.) with http/https ingress, but no load balancer.
This means a single node cluster running some light workloads could run for as little as $6 p/m. (cloud LB's typically cost ~$20 p/m+)

As the name implies, this is **not for HA use cases** - you will have a single entrypoint IP for any apps you serve from the cluster and a single ingress controller pod on the master node handles the routing (aka: single points of failure).

But for *cost-sensitive*, non-HA use cases - and learning - this is ideal. It's a full cluster that you can use in a normal way - point multiple domains to it, route them to your apps and scale with additional worker nodes as the workload demand grows. Just not with 99.9999% uptime.


## The Setup

* We will be using the `baremetal` version of the `ingress-nginx` controller
    * https://kubernetes.github.io/ingress-nginx/
    * modified to bind to the host network and forced to deploy on the master node
* This provides an ingress entrypoint to the cluster
    * The master node must have a public IP if you want to access apps from the outside world
* After that you just deploy nginx ingresses and your apps services + pods in the normal way
* Simple 1 master + 1 worker outlined, but you can scale out worker nodes as required or just run a single master node
    * If you get to the point where you're thinking of scaling the master nodes, you have outgrown this anti-pattern
* Flannel used as the overlay network
    * Calico also tested - see known issues

### Requirements / Pre-requisites

* 1 or more (virtual) servers with root shell access
* k8s supported OS installed - Ubuntu 20.04 covered in this guide
* A public IP bound to the master node
* Working routes between master and worker nodes for the k8s port ranges
    * https://kubernetes.io/docs/reference/ports-and-protocols/


## Build cluster

Skip this section if you know how to deploy a basic kubernetes cluster.

### Install packages on nodes

Optional: apply a hostname to your master(s) + worker(s), eg...

```
ssh nodeuser@nodeip
sudo hostnamectl set-hostname k-master-1
sudo reboot
```

Install Docker, Kubernetes & Flannel on the master(s) AND worker(s)...

```
scp node-setup/ubuntu-20.04.sh nodeuser@nodeip:~/setup.sh
ssh nodeuser@nodeip
chmod +x setup.sh
sudo ./setup.sh
```

NB: you'll be prompted for confirmations several times during the package installs.

### Deploy the cluster

On the master node...

```
sudo kubeadm init --control-plane-endpoint=k8s.yourdomain.com --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

NB: `10.244.0.0/16` is the Flannel default cidr. `--control-plane-endpoint` can be omitted ofc - your cluster, your rules.

On the worker node(s), join the cluster...

```
sudo kubeadm join k8s.yourdomain.com:6443 --token clustertoken \
        --discovery-token-ca-cert-hash clustercertsha256
```

You should now be able to run `kubectl` commands on the master node. 
You will want to setup remote access using RBAC roles, rolebindings, clusterrolebindings etc.
The remainder of the commands can be run remotely by a user assigned the `cluster-admin` ClusterRole

### Deploy Flannel Pod Overlay Network

```
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

NB: if using a different `--pod-network-cidr` you'll need to edit the manifest.


## Setup `noha-k8s` ingress controller

Lovely cluster you have there... time to hit it with the `noha` hammer!

### Allow pods to be scheduled on the master

For our low cost setup we will be using the master to run some pods (notably the ingress controller pod below), remove the taint to allow this...

```
kubectl taint nodes --all node-role.kubernetes.io/control-plane- node-role.kubernetes.io/master-
```

### Deploy ingress-nginx controller with host network binding

We need 1 instance of the ingress-nginx-controller pod on the master node.
So we apply a `dedicated=master` label to the master, which we'll use to target it in the deployment manifest...

```
kubectl label nodes k-master-1 dedicated=master
```

We use the `baremetal` ingress controller manifest from `ingress-nginx` project...

https://github.com/kubernetes/ingress-nginx/blob/main/deploy/static/provider/baremetal/1.23/deploy.yaml

But with some tweaks...

* Remove the service resources & associated admission resources / references
    * The service exists to bind pods across the nodes to external IP(s) - HAProxy or somesuch
    * In our case we are binding a single pod to the host network, so we can save the resources
    * Remove any resources that are `name`'d `ingress-nginx-admission` in their `metadata`
        * services, rbac etc.
    * Remove the `webhook-cert`'s `volume` and `volumeMount`
* Modify the ingress-controller deployment:
    * Modify the `template`: `spec`:
        * Target the master node using `nodeSelector`:
            * `dedicated: master`
        * `hostNetwork: true`
        * `dnPolicy: ClusterFirstWithHost` 
        * Remove the `validating-webhook` env vars & `webhook` container port mapping 
            * We've removed the service
    * You may want adjust other things here such as `resoucreLimits`

Apply the modified ingress-nginx-controller manifest...

```
kubectl apply -f https://raw.githubusercontent.com/SpoddyCoder/noha-k8s/master/deploy/ingress-nginx-controller.yaml
```

See the diff between the original and modified here...

https://github.com/blah


## Deploy an app

This can be done in the normal way, using an `ingress` with `ingressClassName: nginx` to forward the requests to the app service. 
See the `deploy/example-app.yaml` for a simple working example...

```
kubectl apply -f deploy/example-app.yaml
```

Make sure port 80 is open on the master, visit `http://yourmasterip` and you should be greeted with an nginx welcome page.
To see what node is running which pods...

```
kubectl get pod --all-namespaces -o wide
```

## Known Issues

* Ubuntu 22.04 (AWS image) could not deploy cluster succesfully using `kubeadm`
    * The kube-system pods repeatedly crashed
    * Untested: other Ubuntu22.04 images
* Calico overlay network did not work
    * the ingress-nginx-controller pod on the master node could not communicate with pods on other nodes
    * checked everything, could find no reason - switching to Flannel immediately resolved ¯\_(ツ)_/¯


## Useful resources

https://kubernetes.github.io/ingress-nginx/deploy/baremetal/#via-the-host-network
https://ghostsquad.me/posts/kubernetes-on-the-cheap-part-1/#create-a-gke-cluster


## Contributing

Contributions very welcome! Something wrong? Could be better? Additional use-cases?
Please post in the issues forum or submit a PR.