# cm-gke-as
# Codemender GKE Agent Sandbox

This repository provides a minimal, secure implementation for running the Google Cloud Codemender client (CMOC) in a highly isolated environment using Google Kubernetes Engine (GKE) Agent Sandbox.

## Architecture

The sandbox uses GKE Autopilot with the Agent Sandbox (gVisor) feature enabled. Network traffic is isolated using a private VPC and Private Google Access for Google APIs.

Here a custom controller to manage the lifecycle of the sandbox instances.  A sanbox CRD is the primary resource that represents a single, stateful Pod.  It manages the hostnames, identity and persistent storage.  A planned enhancement will add a sandbox router to provide stable endpoints and tunnel traffic to appropriate sandbox pods.  By integrating GKE Pod snapshots, these workloads can be paused and resumed by saving the full state of the container.

The sandbox implements a Default Deny network security posture for all sandboxed environments. This ensures that untrusted code executed inside a sandbox cannot access unauthorized internal networks or the GKE control plane by default. You can define specific network restrictions and allow egress or ingress rules within your SandboxTemplate to provide fine-grained security for specific workloads.

A key feature of this system is the Claim Model that separates the user’s request for an environment (perhaps managed by a platform engineering team) from the specific implementation details.  It lets you request an environment without having to manage the underlying Pod or storage directly.   The request is managed using the SandboxClaim and SandboxTemplate CRDs. To minimize startup latency, a warm pool is used.  This feature allows the Agent Sandbox to provide execution environments in less then one second.  The feature is managed using the SandboxWarmPool CRD. 

Google Cloud storage buckets are presented in the pods through a GCS Fuse mount to ease the input and output of source code and report data.  

## ToDos

Integrate agent sandbox router functionality to allow usage of the environment remotely via programmatic calls from a pipeline or command line. ( reference https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox )

## Prerequisites

1.  **Google Cloud SDK (`gcloud`)** installed and authenticated.
2.  **Terraform** (`>= 1.3.0`) installed.
3.  A Google Cloud Project with billing enabled.

*(Note: Local Docker and `envsubst` are **not** required; container images are built in the cloud via Google Cloud Build, and template substitution uses standard `sed`.)*

## Deployment Instructions

### 1. Configure Variables (`terraform.tfvars`)

Copy the example variables file and set your `project_id`:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:
```hcl
project_id  = "your-google-cloud-project-id"
region      = "us-central1" # Optional, defaults to us-central1
prefix      = "cm-sandbox"  # Optional, defaults to cm-sandbox
target_repo = "https://github.com/thepawn1/cyber-homegym.git" # Optional, set to "none" to skip

# Optional: VPC Service Controls Perimeter
enable_vpc_sc    = false
access_policy_id = "" # Set to numeric Access Policy ID if enable_vpc_sc is true
```

*(Alternatively, you can export `PROJECT_ID` and `TARGET_REPO` as environment variables).*

### 2. Run the Deployment Script

The `deploy.sh` script automates the entire process:
1. Provisions infrastructure, builds/pushes the Codemender container image to Artifact Registry, and deploys Kubernetes manifests (PVC, SandboxTemplate, SandboxWarmPool, SandboxClaim, RBAC) via Cloud Build (orchestrated by Terraform).
2. Clones the `target_repo` into `/tmp` and uploads it to the created GCS source bucket.

```bash
./deploy.sh
```

## Using Codemender

### 1. Prepare Source Code
By default, `deploy.sh` automatically stages the repository configured in `target_repo` into `/tmp` and uploads it to your GCS source bucket.

- **Custom Repository**: Change `target_repo` in `terraform/terraform.tfvars` or export `TARGET_REPO="https://github.com/..."`.
- **Skip Auto-Staging**: Set `target_repo = "none"` in `terraform/terraform.tfvars`.
- **Manual Upload**: You can manually upload any local directory:
```bash
export SRC_BUCKET=$(terraform -chdir=terraform output -raw src_bucket_name)
gcloud storage cp -r /path/to/your-repo/ "gs://${SRC_BUCKET}/" --project="${PROJECT_ID}"
```

### 2. Connect to the Sandbox
Drop into an interactive shell inside the secure, isolated gVisor sandbox. The container environment has the source bucket mounted at `/workspace/src` and the output bucket mounted at `/workspace/out`.

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

## Clean Up

To avoid incurring charges, destroy the infrastructure when finished:

```bash
cd terraform
terraform destroy
```
