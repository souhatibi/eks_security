################ Network Policies ################

# Verify the version of Amazon VPC CNI plugin of the cluster

kubectl describe daemonset aws-node --namespace kube-system | grep amazon-k8s-cni: | cut -d : -f 3

# Create Amazon EKS VPC CNI Managed add-on with configuration to enable Network Policy Agent and also enable ClodWatch logs.

aws eks create-addon \
    --cluster-name EKS \
    --addon-name vpc-cni \
    --addon-version <VPC_CNI_VERSION> \
    --resolve-conflicts OVERWRITE \
    --configuration-values '{"enableNetworkPolicy": "true", "nodeAgent": {"enableCloudWatchLogs": "true"}}' --region eu-west-3

# Deploy environment to test network policies

kubectl apply -f network_policies/app_manifests

# Verify that pods are running in default namespace

kubectl get all

# Verify that pods are running in tenant namespace

kubectl get all -n tenant-ns

# Verify the connectivity between client pods to demo-app pod within same default namespace.

kubectl exec -it client-one -- curl --max-time 3 app-svc

kubectl exec -it client-two -- curl --max-time 3 app-svc

# Verify the connectivity between the tenant pod to demo-app pod across namespaces

kubectl exec -it tenant-client-one -n tenant-ns -- curl --max-time 3 app-svc.default

# Block all traffic from all clients to demo-app

kubectl apply -f network_policies/policies_manifests/01_deny_all_ingress.yaml

kubectl delete -f network_policies/policies_manifests/01_deny_all_ingress.yaml

# Allow ingress traffic within same namespace to demo-app

kubectl apply -f network_policies/policies_manifests/02_allow_ingress_within_same_ns.yaml

kubectl delete -f network_policies/policies_manifests/02_allow_ingress_within_same_ns.yaml

# Allow ingress traffic from only client-one to demo-app

kubectl apply -f network_policies/policies_manifests/03_allow_ingress_from_same_ns_client_one.yaml

kubectl delete -f network_policies/policies_manifests/03_allow_ingress_from_same_ns_client_one.yaml

# Allow ingress traffic from tenant-ns namespace to demo-app 

kubectl apply -f network_policies/policies_manifests/04_allow_ingress_from_tenant_ns.yaml

kubectl delete -f network_policies/policies_manifests/04_allow_ingress_from_tenant_ns.yaml

# Deny all egress from client-one pod

kubectl apply -f network_policies/policies_manifests/05_deny_egress_from_client_one.yaml

kubectl delete -f network_policies/policies_manifests/05_deny_egress_from_client_one.yaml

# Allow egress to a specific port(53) on coredns from client-one pod

kubectl apply -f network_policies/policies_manifests/06_allow_egress_to_coredns.yaml

kubectl delete -f network_policies/policies_manifests/06_allow_egress_to_coredns.yaml

# Allow egress to coredns and demo-app from client-one pod

kubectl apply -f network_policies/policies_manifests/07_allow_egress_to_demo_app.yaml

kubectl delete -f network_policies/policies_manifests/07_allow_egress_to_demo_app.yaml

################ Security Groups for Pods ################

# Create security groups for RDS and green pod

chmod +x create_sgs.sh

./create_sgs.sh

# Create RDS

chmod +x create_rds.sh 

./create_rds.sh

# Get endpoint of RDS after it finishs creating

export RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier rds-eks \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text \
    --region eu-west-3) && echo "RDS endpoint: ${RDS_ENDPOINT}"

# Install mysql client 

brew install mysql-client

mysql --version

# Create content in RDS database 

export RDS_PASSWORD=$(cat ./rds_password)

mysql -h ${RDS_ENDPOINT} -u eks -p${RDS_PASSWORD} < ./mysql.sql

# Add the policy AmazonEKSVPCResourceController to a eks cluster role

aws iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController \
    --role-name EKSClusterRole

# Enable the CNI plugin to manage network interfaces

kubectl -n kube-system set env daemonset aws-node ENABLE_POD_ENI=true

# Check the rolling update of the daemonset

kubectl -n kube-system rollout status ds aws-node

# Create security group policy

export POD_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=POD_SG \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3)

cat << EoF > ./sg_policy.yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: allow-rds-access
spec:
  podSelector:
    matchLabels:
      app: green-pod
  securityGroups:
    groupIds:
      - ${POD_SG}
EoF

kubectl apply -f sg_policy.yaml

kubectl describe securitygrouppolicy

# Create Kubernetes secret

kubectl create secret generic rds \
    --from-literal="password=${RDS_PASSWORD}" \
    --from-literal="host=${RDS_ENDPOINT}"

kubectl describe secret rds

# Deploy green pod

kubectl apply -f green_pod.yaml

export GREEN_POD_NAME=$(kubectl -l app=green-pod -o jsonpath='{.items[].metadata.name}')

kubectl logs -f ${GREEN_POD_NAME}

kubectl describe pod $GREEN_POD_NAME | head -11

# Deploy red pod

kubectl apply -f red_pod.yaml

export RED_POD_NAME=$(kubectl -l app=red-pod -o jsonpath='{.items[].metadata.name}')

kubectl logs -f ${RED_POD_NAME}

kubectl describe pod $RED_POD_NAME | head -11

# Cleanup

chmod +x cleanup.sh

./cleanup.sh

# Finish cleanup : delete DB subnet group
aws rds delete-db-subnet-group \
    --db-subnet-group-name rds-eks \
    --region eu-west-3








