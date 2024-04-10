#!/bin/bash

export VPC_ID=$(aws eks describe-cluster \
    --name EKS \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text \
    --region eu-west-3)

export RDS_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=RDS_SG Name=vpc-id,Values=${VPC_ID} \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3)

export POD_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=POD_SG Name=vpc-id,Values=${VPC_ID} \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3)

export ENI_ID=$(aws ec2 describe-network-interfaces \
    --filters Name=group-id,Values=${POD_SG} \
    --query 'NetworkInterfaces[*].NetworkInterfaceId' \
    --output text \
    --region eu-west-3)

export MY_IP=$(curl icanhazip.com -4)

export NODE_GROUP_SG=$(aws ec2 describe-security-groups \
    --filters Name=tag:Name,Values=eks-SecurityGroup \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region eu-west-3)

export CONTROL_PLANE_SG=$(aws ec2 describe-security-groups \
    --filters Name=tag:aws:eks:cluster-name,Values=EKS \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region eu-west-3)

# Delete database

aws rds delete-db-instance \
    --db-instance-identifier rds-eks \
    --delete-automated-backups \
    --skip-final-snapshot \
    --region eu-west-3

# Delete kubernetes elements

kubectl delete -f ./green_pod.yaml
kubectl delete -f ./red_pod.yaml
kubectl delete -f ./sg_policy.yaml
kubectl delete secret rds

# Disable ENI trunking

kubectl -n kube-system set env daemonset aws-node ENABLE_POD_ENI=false
kubectl -n kube-system rollout status ds aws-node

# Detach the IAM policy

aws iam detach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController \
    --role-name EKSClusterRole

# Remove the security groups rules

aws ec2 revoke-security-group-ingress \
    --group-id ${RDS_SG} \
    --protocol tcp \
    --port 3306 \
    --source-group ${POD_SG} \
    --region eu-west-3

aws ec2 revoke-security-group-ingress \
    --group-id ${RDS_SG} \
    --protocol tcp \
    --port 3306 \
    --cidr ${MY_IP}/32 \
    --region eu-west-3

aws ec2 revoke-security-group-ingress \
    --group-id ${NODE_GROUP_SG} \
    --protocol tcp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

aws ec2 revoke-security-group-ingress \
    --group-id ${NODE_GROUP_SG} \
    --protocol udp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

aws ec2 revoke-security-group-ingress \
    --group-id ${CONTROL_PLANE_SG} \
    --protocol tcp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

aws ec2 revoke-security-group-ingress \
    --group-id ${CONTROL_PLANE_SG} \
    --protocol udp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

aws ec2 delete-network-interface \
    --network-interface-id ${ENI_ID} \
    --region eu-west-3

# Delete POD security group

aws ec2 delete-security-group \
    --group-id ${POD_SG} \
    --region eu-west-3 

# Delete RDS SG
aws ec2 delete-security-group \
    --group-id ${RDS_SG} \
    --region eu-west-3
