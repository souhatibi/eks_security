# Install Kyverno using a YAML manifest (for production it is recommended to use Helm)

kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.10.0/install.yaml

# Uninstall Kyverno 

kubectl delete -f https://github.com/kyverno/kyverno/releases/download/v1.10.0/install.yaml

# List all provisioned resources by Kyvenro

kubectl get all -n kyverno

# Create a pod with nginx image from any available docker registry

kubectl run nginx --image=nginx

# Display nginx image used for the container

kubectl describe pod nginx | grep Image

# Apply cluster policy that allows images only from AWS ECR registry

kubectl apply -f restrict_registries.yaml

# Create a pod with nginx image

kubectl run nginx --image=nginx

# Create a pod with nginx image from ECR registry

kubectl run nginx-ecr --image=public.ecr.aws/nginx/nginx

# Delete pod 

kubectl delete pod nginx-ecr 

# Create 2 pods with latest nginx image from ECR registry

kubectl run nginx-1 --image=public.ecr.aws/nginx/nginx:latest

kubectl run nginx-2 --image=public.ecr.aws/nginx/nginx:latest

# Delete the second pod 

kubectl delete pod nginx-2

# Apply mutating policy that set imagePullPolicy to IfNotPresent if the image tag is latest: 

kubectl apply -f mutating_policy.yaml

# View policy reports

kubectl get policyreports

# Create namespace to test psa

kubectl create namespace psa 

# Run a privileged pod

kubectl run privileged-nginx --image nginx -n psa --privileged

# Create deployment with privileged pods

kubectl apply -f deployment_psa.yaml -n psa 

# View details about deployment 

kubectl get deploy test-psa-deployment -n psa -o yaml

# Create a privileged pod

kubectl apply -f pod_privileged_psa.yaml -n psa

# Create deployment with root privilege 

kubectl apply -f deployment_non_root_user.yaml

# Look for user identity of the container 

kubectl exec <pod_name> -- whoami 

kubectl exec <pod_name> -- id 

# Create a pod with a bad configuration of hostpath

kubectl apply -f bad_pod_with_hostpath.yaml

# Get a shell on the running container 

kubectl exec --stdin --tty bad-pod-hostpath -- /bin/bash

# Create a policy-as-code to restrict hostpath

kubectl apply -f restrict_hostpath_policy.yaml

# Create pod with nginx hostpath

kubectl apply -f pod_nginx_with_hostpath.yaml

# Create new namespace to test request and limits 

kubectl create ns development

# Create a Request quota 

kubectl apply -f resource_quota.yaml

kubectl describe resourcequota cpu-mem-quota -n development

# Create a pod to test requests and limits of memory and cpu

kubectl apply -f pod_with_resources.yaml

# Create a limit range for development namespace 

kubectl apply -f limit_range.yaml

kubectl describe limitrange default-requests-limits -n development

# Create a service 

kubectl apply -f svc.yaml

# Create a pod with service discovery configuration

kubectl apply -f pod_service_discovery.yaml

kubectl exec --stdin --tty service-discovery-pod -- /bin/bash
