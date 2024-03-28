# If your AWS CLI version is earlier than 1.16.139, you must first update to the latest version.
aws --version

# Update your cluster's control plane log export configuration with the following AWS CLI command.
aws eks update-cluster-config \
    --region <region-code> \
    --name EKS \
    --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'

# Log Insight query to identify component in EKS cluster making a high volume of requests to the API server.

fields userAgent, requestURI, @timestamp, @message
| filter @logStream ~= "kube-apiserver-audit"
| stats count(userAgent) as count by userAgent
| sort count desc

# Log Insight query to get the events where the kube-system namespace is used.

fields @timestamp, @message
| sort @timestamp desc
| filter objectRef.namespace like 'kube-system'
| limit 2

# Pattern for metric filter for code 403 response to api-server 

{ $.responseStatus.code = "403" }

# Pattern for metric filter to detect any modification in aws-auth configmap

{( $.objectRef.name = "aws-auth" && $.objectRef.resource = "configmaps" ) && ($.verb = "delete" || $.verb = "create" || $.verb = "patch" || $.verb = "update") }

# Update aws-auth with a new user

eksctl create iamidentitymapping \
    --cluster EKS \
    --region=eu-west-3 \
    --arn arn:aws:iam::$account_id:role/$role \
    --group eks-console-dashboard-restricted-access-group \
    --no-duplicate-arns

# Generate a finding with high severity : Granting the user system:anonymous with access to the view ClusterRole

kubectl apply -f guardduty-anonymous.yaml

# Delete the clusterrole binding of the user system:anonymous

kubectl delete -f  guardduty-anonymous.yaml