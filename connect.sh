#!/usr/bin/env bash
set -e

# Fetch cluster and repo info from Terraform if available
if [ -d "terraform" ] && [ -f "terraform/terraform.tfstate" ]; then
  PROJECT_ID=${PROJECT_ID:-$(terraform -chdir=terraform output -raw project_id 2>/dev/null || echo "")}
  LOCATION=${LOCATION:-$(terraform -chdir=terraform output -raw cluster_location 2>/dev/null || echo "us-central1")}
  CLUSTER_NAME=${CLUSTER_NAME:-$(terraform -chdir=terraform output -raw cluster_name 2>/dev/null || echo "cm-sandbox-cluster")}
  TARGET_REPO=${TARGET_REPO:-$(terraform -chdir=terraform output -raw target_repo 2>/dev/null || echo "")}
fi

PROJECT_ID=${PROJECT_ID:-"$(gcloud config get-value project 2>/dev/null || echo "")"}
LOCATION=${LOCATION:-"us-central1"}
CLUSTER_NAME=${CLUSTER_NAME:-"cm-sandbox-cluster"}

echo "Fetching GKE cluster credentials for ${CLUSTER_NAME}..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${LOCATION}" --project="${PROJECT_ID}"

# Find the active sandbox pod created by the warmpool/claim
POD_NAME=$(kubectl get pods -l sandbox-type=codemender-runtime -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
  echo "Error: Could not find a running Codemender sandbox pod."
  echo "Check 'kubectl get pods' to ensure it is running."
  exit 1
fi

# Determine repo path if staged
SCAN_PATH="/workspace/src"
if [ -n "$TARGET_REPO" ] && [ "$TARGET_REPO" != "none" ]; then
  REPO_NAME=$(basename "$TARGET_REPO" .git)
  SCAN_PATH="/workspace/src/${REPO_NAME}"
fi

echo "Connecting to Codemender sandbox pod: $POD_NAME"
echo "You are now inside the secure gVisor sandbox."
echo ""
echo "Tips for using Codemender:"
echo " - Your source code bucket is mounted at: /workspace/src"
echo " - Your output reports bucket is mounted at: /workspace/out"
if [ "$SCAN_PATH" != "/workspace/src" ]; then
  echo " - Staged repository: ${SCAN_PATH}"
fi
echo " - Codemender writes reports to: ~/.codemender/reports"
echo " - Example commands:"
echo "   cm find --sandbox=false ${SCAN_PATH}"
echo "   cm verify --sandbox=false ${SCAN_PATH}"
echo "   cm verify fix --sandbox=false ${SCAN_PATH}"
echo "   cm report"
echo "   cp -r ~/.codemender/reports/* /workspace/out/"
echo ""
kubectl exec -it $POD_NAME -- /bin/bash
