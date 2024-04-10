#!/bin/bash

export VPC_ID=$(aws eks describe-cluster \
    --name EKS \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text \
    --region eu-west-3)

export PUBLIC_SUBNETS_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Project,Values=aws-eks" \
    --query 'Subnets[*].SubnetId' \
    --region eu-west-3 \
    --output json | jq -c .)

# Create a db subnet group

aws rds create-db-subnet-group \
    --db-subnet-group-name rds-eks \
    --db-subnet-group-description rds-eks \
    --subnet-ids ${PUBLIC_SUBNETS_ID} \
    --region eu-west-3

# Get RDS SG ID

export RDS_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=RDS_SG Name=vpc-id,Values=${VPC_ID} \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3)

# Generate a password for RDS

export RDS_PASSWORD=$(aws secretsmanager get-random-password \
    --exclude-punctuation \
    --password-length 20 --output text \
    --region eu-west-3)

echo $RDS_PASSWORD > ./rds_password

# Create RDS Mysql instance

aws rds create-db-instance \
    --db-instance-identifier rds-eks \
    --db-name eks \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --db-subnet-group-name rds-eks \
    --vpc-security-group-ids $RDS_SG \
    --master-username eks \
    --publicly-accessible \
    --master-user-password ${RDS_PASSWORD} \
    --backup-retention-period 0 \
    --allocated-storage 20 \
    --region eu-west-3

