#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: ./scripts/deploy-hydra.sh <admin|public> <development|staging|production>" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
fi

hydra_service=$1
env=$2
HYDRA_VERSION="${HYDRA_VERSION:-v26.2.0}"

case "$hydra_service" in
  admin|public) ;;
  *) usage ;;
esac

case "$env" in
  development|staging|production) ;;
  *) usage ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"

service_name="ory-hydra-${hydra_service}-${env}"
dockerfile="Dockerfile-${hydra_service}"
image_name="gcr.io/corsali-${env}/ory-hydra-${hydra_service}:${HYDRA_VERSION}"
cloud_project="corsali-${env}"
service_account="vana-app-user@${cloud_project}.iam.gserviceaccount.com"

env_file="$(mktemp)"
hydra_config="$repo_root/hydra.yml"

cleanup() {
  rm -f "$env_file" "$hydra_config"
}

trap cleanup EXIT

echo "Setting up Doppler"
doppler setup --project vana-oauth --config "$env"
doppler secrets download --no-file --format env > "$env_file"

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

for required_var in DATABASE_URL LOGIN_URL ORY_PUBLIC_URL ORY_ADMIN_URL COOKIE_DOMAIN SYSTEM_SECRET COOKIE_SECRET PAGINATION_SECRET OIDC_PAIRWISE_SALT; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "${required_var} is not set" >&2
    exit 1
  fi
done

: "${CORS_DEBUG:=false}"
: "${LOG_LEAK_SENSITIVE_VALUES:=false}"
: "${OAUTH2_EXPOSE_INTERNAL_ERRORS:=false}"

echo "Rendering hydra.yml"
envsubst < hydra.template.yml > "$hydra_config"

echo "Configuring gcloud"
gcloud config set project "$cloud_project"

echo "Build and push docker image"
docker build --no-cache --platform linux/amd64 --build-arg "HYDRA_VERSION=${HYDRA_VERSION}" -t "$image_name" -f "docker/$dockerfile" .
docker push "$image_name"

echo "Verify image exists in registry"
gcloud container images describe "$image_name"

echo "Deploy to Cloud Run"
deploy_args=(
  gcloud run deploy "$service_name"
  --image "$image_name"
  --region us-central1
  --vpc-connector "vpc-conn-${env}"
)

if [[ "$hydra_service" == "admin" ]]; then
  # Hydra admin must stay behind service-to-service auth.
  deploy_args+=(
    --no-allow-unauthenticated
    --service-account "$service_account"
  )
else
  deploy_args+=(--allow-unauthenticated)
fi

"${deploy_args[@]}"
