# Codemender GKE Agent Sandbox

The foundation of this repository comes from [Daniel Lee's repo](https://github.com/thepawn1/cm-gke-as) that moves to the next level of isolation when executing the Codemender binary in a [Google Kubernetes Engine (GKE) Agent Sandbox](https://cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox). This sandbox architecture is the walk phase of isolating the Codemender service to safely detect vulnerabilities in an applications. If you want to backup to the crawl phase, this [repo using Google Compute Engine](https://github.com/jasonbisson/terraform-google-codemender) is straightforward and quick to ramp on the basics of the Codemender service.

## Features

- GKE Autopilot with Agent Sandbox (gVisor feature enabled) for vulnerability remediation 
- Private VPC and Private Google Access for Google APIs
- Custom controller for lifecycle management of sandbox instances. 
- Google Cloud Storage Fuse mount point for application and report sharing   
- Optional VPCSC Perimeter for advanced users. 

## Vulnerability Remediation Workflow

## 🚀 Infrastructure Deployment


### 1. Configure Variables

Copy variables template file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:
```hcl
project_id  = "your-google-cloud-project-id"
region      = "us-central1" # Optional, defaults to us-central1
prefix      = "cm-sandbox"  # Optional, defaults to cm-sandbox
target_repo = "https://github.com/thepawn1/cyber-homegym.git" # Optional, set to "none" to skip

# Optional VPC Service Controls Perimeter for advanced users
enable_vpc_sc    = false
access_policy_id = "" # Set to numeric Access Policy ID if enable_vpc_sc is true
```


### 2. Run the Deployment Script

The `deploy.sh` script automates the entire process:
1. Provisions infrastructure, builds/pushes the Codemender container image to Artifact Registry, and deploys Kubernetes manifests (PVC, SandboxTemplate, SandboxWarmPool, SandboxClaim, RBAC) via Cloud Build (orchestrated by Terraform).
2. Clones the `target_repo` into `/tmp` and uploads it to the created GCS source bucket.

```bash
./deploy.sh
```

## 🧪 Codemender CLI in Agent Sandbox

### 1. Prepare Source Code
By default, `deploy.sh` automatically stages the repository configured in `target_repo` into `/tmp` and uploads it to your GCS source bucket.

- **Custom Repository**: Change `target_repo` in `terraform/terraform.tfvars` or export `TARGET_REPO="https://github.com/..."`.
- **Skip Auto-Staging**: Set `target_repo = "none"` in `terraform/terraform.tfvars`.
- **Manual Upload**: You can manually upload any local directory:
```bash
export SRC_BUCKET=$(terraform -chdir=terraform output -raw src_bucket_name)
gcloud storage cp -r /path/to/your-repo/ "gs://${SRC_BUCKET}/" --project="${PROJECT_ID}"
```

### 2. Connect to the Agent Sandbox
Drop into an interactive shell inside the secure, isolated Agent sandbox. The container environment has the source bucket mounted at `/workspace/src` and the output bucket mounted at `/workspace/out`.

```bash
./connect.sh
```

### 3. Run Codemender Commands
Inside the sandbox, you can run the Codemender client commands against the source code mounted at `/workspace/src`:

> **Note on `--sandbox=false`:**
> - **The `cm` client's internal sandbox**: By default, the `cm` binary tries to create an internal sandbox (a "dispatcher box") to isolate compiler/execution steps using Linux kernel namespaces (via `clone` or `unshare` syscalls like `CLONE_NEWUSER`).
> - **gVisor conflict (`EINVAL`)**: The pod is already running inside GKE Agent Sandbox (gVisor) with `runtimeClassName: gvisor` and restricted security context (`capabilities: drop: [ALL]`, `allowPrivilegeEscalation: false`). When `cm` attempts to create an inner user namespace inside gVisor, gVisor rejects the nested namespace syscall with `EINVAL` (invalid argument).
> - Because the entire pod is already isolated by gVisor, the internal `cm` sandbox is redundant and `--sandbox=false` allows `cm` to execute directly within the gVisor environment.

```bash
# Find vulnerabilities in the source code
cm find --sandbox=false /workspace/src

# Verify findings (can run exploits in the sandbox)
cm verify --sandbox=false /workspace/src

# Attempt to automatically verify and fix findings
cm verify fix --sandbox=false /workspace/src

# Generate reports
cm report
```

### 4. Retrieve Reports
Codemender outputs its HTML and MD reports to `~/.codemender/reports` by default. To retrieve them, copy them from the home directory into the mounted GCS output bucket:

```bash
cp -r ~/.codemender/reports/* /workspace/out/
```

You can then retrieve the reports from the Cloud Storage bucket to your local machine:
```bash
export OUT_BUCKET=$(terraform -chdir=terraform output -raw out_bucket_name)

gcloud storage cp -r "gs://${OUT_BUCKET}/*" ./reports/ --project="${PROJECT_ID}"
```

## 🧹 Clean Up Resources

To avoid incurring charges, destroy the infrastructure when finished:

```bash
cd terraform
terraform destroy
```
