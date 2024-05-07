################ Network Policies ################

cd network_security/

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

cd network_security/

# create kubeconfig file locally 

aws eks update-kubeconfig --region eu-west-3 --name EKS 

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

# Install mysql client (for macOs)

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

export GREEN_POD_NAME=$(kubectl get pods -l app=green-pod -o jsonpath='{.items[].metadata.name}')

kubectl logs -f ${GREEN_POD_NAME}

kubectl describe pod $GREEN_POD_NAME | head -11

# Deploy red pod

kubectl apply -f red_pod.yaml

export RED_POD_NAME=$(kubectl get pods -l app=red-pod -o jsonpath='{.items[].metadata.name}')

kubectl logs -f ${RED_POD_NAME}

kubectl describe pod $RED_POD_NAME | head -11

# Cleanup

chmod +x cleanup.sh

./cleanup.sh

export RDS_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=RDS_SG \
    --query "SecurityGroups[0].GroupId" --output text \
    --region eu-west-3)

# Delete RDS SG
aws ec2 delete-security-group \
    --group-id ${RDS_SG} \
    --region eu-west-3

# Finish cleanup : delete DB subnet group
aws rds delete-db-subnet-group \
    --db-subnet-group-name rds-eks \
    --region eu-west-3

################ Istio Service Mesh ################

cd network_security

# Download Istio installation directory

export ISTIO_VERSION="1.19.0"

curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -

# Install Istio

sudo cp -v ./istio-${ISTIO_VERSION}/bin/istioctl /usr/local/bin/

rm -r ./istio-${ISTIO_VERSION}

# Verify that you have the proper version 

istioctl version --remote=false

# Install all the Istio components using the built-in demo configuration profile

yes | istioctl install --set profile=demo

# Check the Istio pods are running

kubectl -n istio-system get pods

# Deploy frontend nginx

kubectl apply -f istio_frontend.yaml

kubectl get all -n front-end

# Deploy backend api

kubectl apply -f istio_backend.yaml

kubectl get all -n back-end

# Test the communication from nginx pod to api pod 

kubectl exec $(kubectl get pod -l app=nginx -o jsonpath={.items..metadata.name} -n front-end) \
    -c nginx \
    -n front-end \
    -- curl http://api.back-end:8080 \
    -o /dev/null \
    -s -w "From nginx.front-end to api.back-end - HTTP Response Code: %{http_code}\n"

# Enable Istio injection on back-end namespace

kubectl label ns back-end istio-injection=enabled

# Delete and re-create api pod

kubectl delete pod $(kubectl get pod -l app=api -o jsonpath={.items..metadata.name} -n back-end) \
    -n back-end

# Verify if the api pod is injected with istio side-car envoy proxy container

kubectl get pod -n back-end

# Verify the logs of side-car envoy proxy container injected into the api pod

kubectl logs $(kubectl get pod -l app=api -o jsonpath={.items..metadata.name} -n back-end) \
    -n back-end \
    -c istio-proxy | tail -2

# Test communication from nginx pod to api service

kubectl exec $(kubectl get pod -l app=nginx -o jsonpath={.items..metadata.name} -n front-end) \
    -c nginx \
    -n front-end \
    -- curl http://api.back-end:8080 \
    -o /dev/null \
    -s -w "From nginx.front-end to api.back-end - HTTP Response Code: %{http_code}\n"

# Verify the logs of side-car envoy proxy container injected into the api pod

kubectl logs $(kubectl get pod -l app=api -o jsonpath={.items..metadata.name} -n back-end) \
    -n back-end \
    -c istio-proxy | tail -2

# Enable mTLS mode of STRICT on back-end namespace

kubectl apply -f istio_auth.yaml

# Test communication from nginx pod to api service

kubectl exec $(kubectl get pod -l app=nginx -o jsonpath={.items..metadata.name} -n front-end) \
    -c nginx \
    -n front-end \
    -- curl http://api.back-end:8080 \
    -o /dev/null \
    -s -w "From nginx.front-end to api.back-end - HTTP Response Code: %{http_code}\n"

# Enable Istio injection on front-end namespace

kubectl label ns front-end istio-injection=enabled

# Delete and re-create nginx pod

kubectl delete pod $(kubectl get pod -l app=nginx -o jsonpath={.items..metadata.name} -n front-end) \
    -n front-end

# Verify if the nginx pod is injected with istio side-car envoy proxy container

kubectl get po -n front-end

# Test communication from nginx pod to api service

kubectl exec $(kubectl get pod -l app=nginx -o jsonpath={.items..metadata.name} -n front-end) \
    -c nginx \
    -n front-end \
    -- curl http://api.back-end:8080 \
    -o /dev/null \
    -s -w "From nginx.front-end to api.back-end - HTTP Response Code: %{http_code}\n"

# Verify the logs of side-car envoy proxy container injected into the api pod

kubectl logs $(kubectl get pod -l app=api -o jsonpath={.items..metadata.name} -n back-end) \
    -n back-end \
    -c istio-proxy | tail -2

# Cleanup 

kubectl delete -f istio_auth.yaml

kubectl delete -f istio_backend.yaml

kubectl delete -f istio_frontend.yaml

# istioctl uninstall --purge

################# Encryption with load balancers ##################

kubectl apply -f encryption_nlb.yaml

kubectl delete -f encryption_nlb.yaml

################# TLS-enabled Kubernetes clusters with ACM Private CA and Amazon EKS ##################

aws eks update-kubeconfig --region eu-west-3 --name EKS 

# Install NGINX Ingress

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/aws/deploy.yaml

# Find the address that AWS has assigned to the NLB

kubectl get service -n ingress-nginx

# Install cert-manager

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml

# Install helm for macos (Follow the instructions here https://helm.sh/docs/intro/install/ for other OSs )

brew install helm

brew link helm

# Install aws-privateca-issuer

kubectl create namespace aws-pca-issuer

helm repo add awspca https://cert-manager.github.io/aws-privateca-issuer
helm repo update
helm install awspca/aws-privateca-issuer  --generate-name --namespace aws-pca-issuer

# Verify that the AWS Private CA Issuer is configured correctly

kubectl get pods --namespace aws-pca-issuer

# Download the CA certificate after creating the CA on the console

aws acm-pca get-certificate-authority-certificate \
    --certificate-authority-arn <CA_ARN> \
    --region eu-west-3 \
    --output text > cacert.pem

# Set EKS node permission for ACM Private CA

export REGION=eu-west-3
export ACCOUNT_ID=<ACCOUNT_ID>
export CA_ARN=<CA_ARN>

cat << EoF > ./acm_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "awspcaissuer",
            "Action": [
                "acm-pca:DescribeCertificateAuthority",
                "acm-pca:GetCertificate",
                "acm-pca:IssueCertificate"
            ],
			"Effect": "Allow",
            "Resource": "${CA_ARN}"
        }       
    ]
}
EoF

aws iam create-policy --policy-name AcmPolicy --policy-document file://acm_policy.json

aws iam attach-role-policy \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AcmPolicy \
    --role-name <NODE_INSTANCE_ROLE>

# Create an Issuer in Amazon EKS

cat << EoF > ./cluster_issuer.yaml
apiVersion: awspca.cert-manager.io/v1beta1
kind: AWSPCAClusterIssuer
metadata:
          name: root-ca
spec:
          arn: ${CA_ARN}
          region: ${REGION}
EoF

kubectl apply -f cluster_issuer.yaml

kubectl get AWSPCAClusterIssuer

# Create a new namespace that will contain the application 

kubectl create namespace acm-pca

# Create a basic X509 private certificate for the domain

kubectl apply -f create_cert.yaml -n acm-pca

# Verify that the certificate is issued 

kubectl get certificate -n acm-pca

# Check the progress of the certificate

kubectl describe certificate rsa-cert-2048 -n acm-pca

# Check the issued certificate details

kubectl get secret rsa-cert-2048 -n acm-pca -o 'go-template={{index .data "tls.crt"}}' \
    | base64 --decode \
    | openssl x509 -noout -text

# Deploy a demo application

kubectl apply -f private_ca_app.yaml

# Expose and secure the application

kubectl apply -f private_ca_ingress.yaml

# Access the application using TLS

curl https://www.rsa-2048.eks-example.ovh --cacert cacert.pem -v 

# Cleanup

kubectl delete -f private_ca_ingress.yaml

kubectl delete -f private_ca_app.yaml

aws iam detach-role-policy \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AcmPolicy \
    --role-name <NODE_INSTANCE_ROLE>

aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AcmPolicy
 



