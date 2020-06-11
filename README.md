# Running Red Hat Enterprise Linux 7.7 as EKS Worker Nodes
This repository contains scripts to set up EKS worker nodes for Red Hat Enteriprise Linux v7.7. Setup may be done either with or without RHEL Subscription Manager, and a separate script is provided for each.

Defaults to the following EKS / Kubernetes plugins:
* KUBERNETES_BUILD_DATE="2020-04-16"
* CNI_VERSION="v0.6.0"
* CNI_PLUGIN_VERSION="v0.8.5"

Supports the following features:
* AWS SSM
* Docker insecure registries via /etc/docker/daemon.json

## Setup
* Red Hat Enterprise Linux 7.7
![Example AMI](./images/aws-rhel.png "Red Hat Enterprise Linux 7.7")
 
* Kubernetes 1.16.8 on AWS EKS
* Based on public AMI: RHEL-7.7_HVM-20190923-x86_64-0-Hourly2-GP2 - ami-029c0fbe456d58bd1
  * Use as a point of reference only  

## Workflow (No Subscription Manager)
* Provision an EC2 Server with RHEL 7.7
* Install the following dependencies.
```
sudo yum install -y git vim 
```
* Clone this repo
```
git clone https://github.com/codaglobal/aws-eks-rhel-workers.git
cd aws-eks-rhel-workers
sh install-worker.sh
```
* Check the default variables below, and modify them in install-worker.sh if needed

```
BINARY_BUCKET_NAME="amazon-eks"
BINARY_BUCKET_REGION="us-west-2"
AWS_ACCESS_KEY_ID=""
KUBERNETES_BUILD_DATE="2020-04-16"
CNI_VERSION="v0.6.0"
CNI_PLUGIN_VERSION="v0.8.5"
KUBERNETES_VERSION="1.16.8"
```
* If using an insecure Docker repository (e.g., on-prem, export it like this (optional):
```
export DKR_INSECURE="my-insecure-repo:8081"
```
* Execute install-worker.sh

## Workflow (With Subscription Manager)

* Provision an EC2 Server with RHEL 7.7
* Install the following dependencies.
```
sudo yum install -y git vim 
```
* Clone this repo
```
git clone https://github.com/codaglobal/aws-eks-rhel-workers.git
cd aws-eks-rhel-workers
sh install-worker.sh
```
* **REQUIRED:** Export Subscription Manager credentials as either username / password or org / key 
```
# For org / key:
export SM_ORG="${SM_ORG:-null}"
export SM_KEY="${SM_KEY:-null}"

# For username / password:
export SM_USER="${SM_USER:-null}"
export SM_PASS="${SM_PASS:-null}"

```
* Check the default variables below, and modify them in install-worker.sh if needed

```
BINARY_BUCKET_NAME="amazon-eks"
BINARY_BUCKET_REGION="us-west-2"
AWS_ACCESS_KEY_ID=""
KUBERNETES_BUILD_DATE="2020-04-16"
CNI_VERSION="v0.6.0"
CNI_PLUGIN_VERSION="v0.8.5"
KUBERNETES_VERSION="1.16.8"
```
* If using an insecure Docker repository (e.g., on-prem, export it like this (optional):
```
export DKR_INSECURE="my-insecure-repo:8081"
```
* Execute sm-install-worker.sh

## Creating a Node Group

* Create an AMI of this server.
* Update the included cluster.yml file with these parameter changes:
  * "metadata" section:
    *  "name" - name of the target EKS cluster
    * "region" - region of the target EKS cluster
  * "nodeGroups" section:
    * "name" - desired name of the new nodegroup
    * "NodeImageId" - Image ID of the AMI created in the previous step.
    * "desiredCapacity" - desired number of nodes in the group
    * "minSize" - minimum number of nodes in the group
    * "maxSize" - input the minimum and maximum node group size
    * "privateNetworking" - use private subnets for the nodes?
    * "Tags" - AWS tags for the nodes
    * "IAM" - policies to attach to each node
    * "preBootstrapCommands" - shell scripts to run as nodes are created
    * "ssh" / "publicKeyPath" - local path to a public SSH key that will be used to create the nodes
* Provision a CloudFormation stack for the cluster using the updated cluster.yml file:
`
eksctl create nodegroup -f ./eksctl/cluster.yml
` 

## Credit

PowerUpCloud (https://github.com/powerupcloud) originated this code. This is just an update and adaptation for a more recent version of Kubernetes and EKS.
