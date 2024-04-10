#!/bin/bash

# Create the RDS security group 

export VPC_ID=$(aws eks describe-cluster \
    --name EKS \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text \
    --region eu-west-3)

aws ec2 create-security-group \
    --description 'RDS SG' \
    --group-name 'RDS_SG' \
    --vpc-id ${VPC_ID} \
    --region eu-west-3

# Save the security group ID for future use

export RDS_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=RDS_SG Name=vpc-id,Values=${VPC_ID} \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3 ) && echo "RDS security group ID: ${RDS_SG}"

# Create the POD security group

aws ec2 create-security-group \
    --description 'POD SG' \
    --group-name 'POD_SG' \
    --vpc-id ${VPC_ID} \
    --region eu-west-3

# Save the security group ID for future use

export POD_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=POD_SG Name=vpc-id,Values=${VPC_ID} \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3) && echo "POD security group ID: ${POD_SG}"

# Allow POD_SG to connect to NODE_GROUP_SG using TCP 53 for DNS resolution

export NODE_GROUP_SG=$(aws ec2 describe-security-groups \
    --filters Name=tag:Name,Values=eks-SecurityGroup \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region eu-west-3) && echo "Node Group security group ID: ${NODE_GROUP_SG}"

aws ec2 authorize-security-group-ingress \
    --group-id ${NODE_GROUP_SG} \
    --protocol tcp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

# Allow POD_SG to connect to NODE_GROUP_SG using UDP 53 for DNS resolution

aws ec2 authorize-security-group-ingress \
    --group-id ${NODE_GROUP_SG} \
    --protocol udp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

# Allow POD_SG to connect to CONTROL_PLANE_SG using TCP 53 for DNS resolution

export CONTROL_PLANE_SG=$(aws ec2 describe-security-groups \
    --filters Name=tag:aws:eks:cluster-name,Values=EKS \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region eu-west-3) && echo "Control plane security group ID: ${CONTROL_PLANE_SG}"

aws ec2 authorize-security-group-ingress \
    --group-id ${CONTROL_PLANE_SG} \
    --protocol tcp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

# allow POD_SG to connect to NODE_GROUP_SG using UDP 53
aws ec2 authorize-security-group-ingress \
    --group-id ${CONTROL_PLANE_SG} \
    --protocol udp \
    --port 53 \
    --source-group ${POD_SG} \
    --region eu-west-3

# Allow your machine to connect to RDS

export MY_IP=$(curl icanhazip.com -4)

aws ec2 authorize-security-group-ingress \
    --group-id ${RDS_SG} \
    --protocol tcp \
    --port 3306 \
    --cidr ${MY_IP}/32 \
    --region eu-west-3
    
# Allow POD_SG to connect to the RDS

aws ec2 authorize-security-group-ingress \
    --group-id ${RDS_SG} \
    --protocol tcp \
    --port 3306 \
    --source-group ${POD_SG} \
    --region eu-west-3
