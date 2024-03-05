# Create namespaces for each tenant 

kubectl create ns tenant-1

kubectl create ns tenant-2

# Label the node with tenant information

kubectl label nodes <node-name> tenant=tenant-1

# Create a pod for tenant-1 

kubectl apply -f pod_tenant_1.yaml -n tenant-1

# Verify pod placement

kubectl get pod pod-tenant-1 -n tenant-1 -o wide

# Create a pod for tenant-2 

kubectl apply -f pod_tenant_2.yaml -n tenant-2

# Verify pod placement

kubectl get pod pod-tenant-2 -n tenant-2 -o wide

# Delete two tenants pods

kubectl delete pod pod-tenant-1 -n tenant-1

kubectl delete pod pod-tenant-2 -n tenant-2

# Add a taint to a node

kubectl taint node <node-name> tenant=tenant-1:NoSchedule

# Apply Kyverno policies to mutate request adding node affinity and tolerations

kubectl apply -f mutate_nodeaffinity_policy.yaml -n tenant-1

kubectl apply -f mutate_toleration_policy.yaml -n tenant-1

