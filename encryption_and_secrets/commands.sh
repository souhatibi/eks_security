# Install Secret Store CSI Driver using helm

helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

helm install -n kube-system csi-secrets-store \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  secrets-store-csi-driver/secrets-store-csi-driver

# Verify that Secrets Store CSI Driver has started

kubectl --namespace=kube-system get pods -l "app=secrets-store-csi-driver"

# Install AWS Secrets and Configuration Provider(ASCP) 

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# Verify that csi-secrets-store-provider-aws has started

kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws

# Create a secret in AWS Secret Manager

aws --region eu-west-3 secretsmanager \
  create-secret --name dbsecret_eks \
  --secret-string '{"username":"db_user", "password":"db_secret"}'

SECRET_ARN=$(aws --region "eu-west-3" secretsmanager \
    describe-secret --secret-id  dbsecret_eks \
    --query 'ARN' | sed -e 's/"//g' )

echo $SECRET_ARN

# Create an IAM Policy that will provide permissions to access the secret

IAM_POLICY_NAME_SECRET="dbsecret_eks_secrets_policy"

IAM_POLICY_ARN_SECRET=$(aws --region "eu-west-3" iam \
	create-policy --query Policy.Arn \
    --output text --policy-name $IAM_POLICY_NAME_SECRET \
    --policy-document '{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["'"$SECRET_ARN"'" ]
    } ]
}')

echo $IAM_POLICY_ARN_SECRET | tee -a 00_iam_policy_arn_dbsecret


# Create an IAM OIDC identity provider

# determine if you already have an oidc provider

oidc_id=$(aws eks describe-cluster --name EKS --query "cluster.identity.oidc.issuer" --region eu-west-3 --output text | cut -d '/' -f 5)

aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4

# otherwise create an oidc

eksctl utils associate-iam-oidc-provider --cluster EKS --approve --region eu-west-3

# Configure a Kubernetes service account to assume an IAM role

eksctl create iamserviceaccount \
    --region="eu-west-3" --name "nginx-deployment-sa"  \
    --role-name nginx-deployment-sa-role --cluster "EKS" \
    --attach-policy-arn "$IAM_POLICY_ARN_SECRET" --approve \
    --override-existing-serviceaccounts

# Confirm that the IAM role's trust policy is configured correctly.

export ROLE_NAME="nginx-deployment-sa-role"

aws iam get-role --role-name $ROLE_NAME --query Role.AssumeRolePolicyDocument

# Confirm that the Kubernetes service account is annotated with the role.

kubectl describe serviceaccount nginx-deployment-sa -n default

# Create SecretProviderClass to specify which secret to mount in the pod

cat << EOF > nginx-deployment-spc.yaml
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: nginx-deployment-spc
spec:
  provider: aws
  parameters:
    objects: |
        - objectName: "dbsecret_eks"
          objectType: "secretsmanager"
EOF

kubectl apply -f nginx-deployment-spc.yaml

kubectl get SecretProviderClass

# Deploy POD and Mount secret in the POD

cat << EOF > nginx-deployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      serviceAccountName: nginx-deployment-sa
      containers:
      - name: nginx-deployment
        image: nginx
        ports:
        - containerPort: 80
        volumeMounts:
        - name: secrets-store-inline
          mountPath: "/mnt/secrets"
          readOnly: true
      volumes:
      - name: secrets-store-inline
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: nginx-deployment-spc
EOF

# Create a deployment and verify creation of PODs

kubectl apply -f nginx-deployment.yaml

kubectl get pods -l app=nginx -o wide

# Verify the mounted secret

kubectl exec $(kubectl get pods | awk '/nginx-deployment/{print $1}' | head -1) -- cat /mnt/secrets/dbsecret_eks; echo

#### Secret Rotation ####

aws secretsmanager put-secret-value \
    --secret-id dbsecret_eks \
    --secret-string "{\"username\":\"newdb_user\",\"password\":\"newdb-secret \"}" \
    --region eu-west-3

# Verify the result

export POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[].metadata.name}')

kubectl exec -it ${POD_NAME} -- /bin/bash

# Run these commmands on the pod's shell 

export PS1='# '
cd /mnt/secrets
cat dbsecret_eks; echo

# cleanup

kubectl delete -f nginx-deployment.yaml

rm nginx-deployment.yaml

kubectl delete -f nginx-deployment-spc.yaml

rm nginx-deployment-spc.yaml

eksctl delete iamserviceaccount \
    --region="eu-west-3" --name "nginx-deployment-sa"  \
    --cluster "EKS" 

aws --region "eu-west-3" iam \
	delete-policy --policy-arn $(cat 00_iam_policy_arn_dbsecret)

unset IAM_POLICY_ARN_SECRET

unset IAM_POLICY_NAME_SECRET

rm 00_iam_policy_arn_dbsecret

aws --region "eu-west-3" secretsmanager \
  delete-secret --secret-id  dbsecret_eks --force-delete-without-recovery

kubectl delete -f \
 https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

helm uninstall -n kube-system csi-secrets-store

helm repo remove secrets-store-csi-driver



