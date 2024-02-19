#!/bin/bash

# create kubeconfig file locally 

aws eks update-kubeconfig --region eu-west-3 --name EKS 

# create full access clusterRole and clusterRoleBinding

kubectl apply -f eks-console-full-access.yaml 

# view current mappings in the aws-auth configMap the cluster

eksctl get iamidentitymapping --cluster EKS --region=eu-west-3

# map you IAM principal to Kubernetes group in aws-auth ConfigMap,
# replace $account_id with your account id 

eksctl create iamidentitymapping \
    --cluster EKS \
    --region=eu-west-3 \
    --arn arn:aws:iam::$account_id:user/$user \
    --group eks-console-dashboard-full-access-group \
    --no-duplicate-arns

# view the mappings in the ConfigMap again

eksctl get iamidentitymapping --cluster EKS --region=eu-west-3

# delete an identity mapping (user)

eksctl delete iamidentitymapping \
    --cluster EKS \
    --region=eu-west-3 \
    --arn arn:aws:iam::$account_id:user/$user

# create an identity mapping (role)

eksctl create iamidentitymapping \
    --cluster EKS \
    --region=eu-west-3 \
    --arn arn:aws:iam::$account_id:role/$role \
    --group eks-console-dashboard-restricted-access-group \
    --no-duplicate-arns

# delete an identity mapping (role)

eksctl delete iamidentitymapping \
    --cluster EKS \
    --region=eu-west-3 \
    --arn arn:aws:iam::$account_id:role/$role

# update authentication mode to API_AND_CONFIG_MAP

aws eks update-cluster-config \
    --name EKS \
    --access-config authenticationMode=API_AND_CONFIG_MAP \
    --region=<region-id>

# list access policies

aws eks list-access-policies --region=eu-west-3

# create access entry

aws eks create-access-entry \
    --cluster-name EKS \
    --principal-arn "arn:aws:iam::<ACCOUNT-ID>:user/eks-user" \
    --region=eu-west-3

# associate admin access policy to the access entry

aws eks associate-access-policy \
    --cluster-name EKS \
    --principal-arn "arn:aws:iam::<ACCOUNT-ID>:user/eks-user" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
    --access-scope '{"type": "cluster"}' \
    --region=eu-west-3

# understand level of access of an aws principal

aws eks describe-access-entry \
  --cluster-name EKS \
  --principal-arn "arn:aws:iam::<ACCOUNT-ID>:user/eks-user" \
  --region=eu-west-3

# delete cluster creator admin access

aws eks disassociate-access-policy --cluster-name EKS \
    --principal-arn "arn:aws:iam::<ACCOUNT-ID>:user/eks-admin" \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --region=eu-west-3

# Create a pod with default service account

kubectl apply -f default-sa-pod.yaml

# Create a service account

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
EOF

# Create a view rolebinding and assign it the service account

kubectl create rolebinding my-sa-view \
  --clusterrole=view \
  --serviceaccount=default:my-sa \
  --namespace=default

# Create a pod with custom service account

kubectl apply -f sa-pod.yaml

# Create an IAM OIDC identity provider for the cluster

eksctl utils associate-iam-oidc-provider --region=eu-west-3 --cluster EKS --approve

# Verify if the OIDC was created

aws iam list-open-id-connect-providers

# Create an IAM policy

aws iam create-policy --policy-name s3-policy --policy-document file://s3-policy.json

# Create an IAM role and associate it with a Kubernetes service account (create an IAM role and attach a policy to it)

eksctl create iamserviceaccount --region=eu-west-3 --name my-service-account --cluster EKS --role-name my-role \
    --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/s3-policy --approve

# Check if the service account was created

kubectl describe serviceaccount my-service-account

# Create a deployment to test connectivity between the pod and s3

kubectl apply -f irsa-deployment.yaml

kubectl get pods

kubectl logs -l app=my-app -c demo-aws-cli

# Update worker node (ec2 instance) to require using IMDSv2

aws ec2 modify-instance-metadata-options --instance-id <value> --http-tokens required --http-put-response-hop-limit 1 --region=eu-west-3

# Connect to the ubuntu pod

kubectl exec --stdin --tty ubuntu -- /bin/bash

# Patch default service account to disable auto-mounting of service taccount tokens 

kubectl patch serviceaccount default -p $'automountServiceAccountToken: false'

# Install rbac-lookup tool that will (macOs users)
# RBAC Lookup is a CLI that allows you to easily find Kubernetes roles and cluster roles bound 
# to any user, service account, or group name.

brew install FairwindsOps/tap/rbac-lookup

# Identify permissions that system:anonymous and system:unauthenticated users have on the cluster

rbac-lookup | grep 'system:anonymous'

rbac-lookup | grep 'system:unauthenticated'

# Check if system:unauthenticated group has system:discovery permissions

kubectl describe clusterrolebindings system:discovery

# Check if system:unauthenticated group has system:basic-user permissions

kubectl describe clusterrolebindings system:basic-user

# Check and remove manually system:discovery permissions from system:unauthenticated group

kubectl edit clusterrolebindings system:discovery

# Check and remove manually system:basic-user permissions from system:unauthenticated group

kubectl edit clusterrolebindings system:basic-user

