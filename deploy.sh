#!/usr/bin/env bash
set -e

echo "======================================"
echo "1. Applying Terraform Configuration"
echo "======================================"

cd terraform
set +e
terraform init
if [ $? -eq 0 ]; then
  echo "Terraform init succeeded!"
else
  echo "Terraform init failed!"
  exit 1
fi
set -e
terraform apply -auto-approve

# Extract Terraform outputs
export PROJECT_ID=${PROJECT_ID:-$(terraform output -raw project_id 2>/dev/null || echo "")}
export SRC_BUCKET=$(terraform output -raw src_bucket_name)
export OUT_BUCKET=$(terraform output -raw out_bucket_name)
export TARGET_REPO=${TARGET_REPO:-$(terraform output -raw target_repo 2>/dev/null || echo "")}
cd ..

if [ -n "$TARGET_REPO" ] && [ "$TARGET_REPO" != "none" ]; then
  echo "======================================"
  echo "2. Staging Source Code to GCS (via /tmp)"
  echo "======================================"
  REPO_NAME=$(basename "$TARGET_REPO" .git)
  STAGING_DIR="/tmp/${REPO_NAME}"

  if [ ! -d "$STAGING_DIR" ]; then
    echo "Cloning $TARGET_REPO into $STAGING_DIR..."
    git clone "$TARGET_REPO" "$STAGING_DIR"
  else
    echo "Pulling latest changes in $STAGING_DIR..."
    (cd "$STAGING_DIR" && git pull)
  fi

  echo "Uploading $STAGING_DIR to gs://${SRC_BUCKET}/..."
  gcloud storage cp -r "$STAGING_DIR" "gs://${SRC_BUCKET}/" --project="${PROJECT_ID}"
fi

echo "======================================"
echo "Deployment Complete!"
echo "Source Bucket: gs://${SRC_BUCKET}"
echo "Output Bucket: gs://${OUT_BUCKET}"
echo "Connect to sandbox with: ./connect.sh"
echo "======================================"
