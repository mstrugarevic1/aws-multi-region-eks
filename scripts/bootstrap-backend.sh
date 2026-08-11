#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 BUCKET_NAME [AWS_REGION]" >&2
  exit 1
fi

bucket=$1
region=${2:-eu-central-1}
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  if [[ $region == us-east-1 ]]; then
    aws s3api create-bucket --bucket "$bucket" --region "$region" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --region "$region" \
      --create-bucket-configuration "LocationConstraint=$region" >/dev/null
  fi
fi

aws s3api put-bucket-versioning \
  --bucket "$bucket" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$bucket" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$bucket" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

mkdir -p "$repo_dir/terraform/bootstrap"
printf 'bucket = "%s"\nregion = "%s"\n' "$bucket" "$region" > "$repo_dir/terraform/bootstrap/backend.hcl"

echo "Backend bucket ready: $bucket ($region)"

