#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: ./scripts/deploy-hydra.sh <admin|public> <development|production>" >&2
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
  development|production) ;;
  *) usage ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"

service_name="ory-hydra-${hydra_service}-${env}"
if [[ "$env" == "production" ]]; then
  service_name="${service_name}-v2"
fi
dockerfile="Dockerfile-${hydra_service}"
cloud_project="corsali-${env}"
image_name="gcr.io/${cloud_project}/ory-hydra-${hydra_service}:${HYDRA_VERSION}"
if [[ "$env" == "production" ]]; then
  image_name="us-docker.pkg.dev/${cloud_project}/docker/ory-hydra-${hydra_service}:${HYDRA_VERSION}"
fi
service_account="vana-app-user@${cloud_project}.iam.gserviceaccount.com"

env_file="$(mktemp)"
secret_value_file="$(mktemp)"

cleanup() {
  rm -f "$env_file" "$secret_value_file"
}

trap cleanup EXIT

echo "Setting up Doppler"
doppler setup --project vana-oauth --config "$env"
doppler secrets download --no-file --format env > "$env_file"

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

for required_var in DATABASE_URL LOGIN_URL DEVICE_URL ORY_PUBLIC_URL ORY_ADMIN_URL COOKIE_DOMAIN SYSTEM_SECRET COOKIE_SECRET PAGINATION_SECRET OIDC_PAIRWISE_SALT; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "${required_var} is not set" >&2
    exit 1
  fi
done

: "${CORS_DEBUG:=false}"
: "${LOG_LEAK_SENSITIVE_VALUES:=false}"
: "${OAUTH2_EXPOSE_INTERNAL_ERRORS:=false}"

echo "Configuring gcloud"
gcloud config set project "$cloud_project"

secret_env_vars=(
  DATABASE_URL
  SYSTEM_SECRET
  COOKIE_SECRET
  PAGINATION_SECRET
  OIDC_PAIRWISE_SALT
)

sync_secret_manager="${SYNC_SECRET_MANAGER:-false}"
secret_specs=()
for key in "${secret_env_vars[@]}"; do
  secret_name="ory-hydra-${env}-$(echo "$key" | tr '[:upper:]_' '[:lower:]-')"
  secret_version="latest"
  if [[ "$env" == "production" && "$key" == "SYSTEM_SECRET" ]]; then
    secret_version="${HYDRA_PRODUCTION_SYSTEM_SECRET_VERSION:-1}"
  fi
  if [[ "$sync_secret_manager" == "true" ]]; then
    if ! gcloud secrets describe "$secret_name" >/dev/null 2>&1; then
      gcloud secrets create "$secret_name" --replication-policy=automatic >/dev/null
    fi
    printf "%s" "${!key}" > "$secret_value_file"
    gcloud secrets versions add "$secret_name" --data-file="$secret_value_file" >/dev/null
    gcloud secrets add-iam-policy-binding "$secret_name" \
      --member "serviceAccount:${service_account}" \
      --role roles/secretmanager.secretAccessor >/dev/null
  fi
  secret_specs+=("${key}=${secret_name}:${secret_version}")
done

secret_specs_csv="$(IFS=,; echo "${secret_specs[*]}")"
env_vars_csv="LOGIN_URL=${LOGIN_URL},DEVICE_URL=${DEVICE_URL},ORY_PUBLIC_URL=${ORY_PUBLIC_URL},ORY_ADMIN_URL=${ORY_ADMIN_URL},COOKIE_DOMAIN=${COOKIE_DOMAIN},CORS_DEBUG=${CORS_DEBUG},LOG_LEAK_SENSITIVE_VALUES=${LOG_LEAK_SENSITIVE_VALUES},OAUTH2_EXPOSE_INTERNAL_ERRORS=${OAUTH2_EXPOSE_INTERNAL_ERRORS}"

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
  --set-env-vars "$env_vars_csv"
  --update-secrets "$secret_specs_csv"
  --vpc-connector "vpc-conn-${env}"
  --service-account "$service_account"
)

if [[ "$hydra_service" == "admin" ]]; then
  # Hydra admin must stay behind service-to-service auth.
  deploy_args+=(
    --no-allow-unauthenticated
  )
else
  deploy_args+=(--allow-unauthenticated)
fi

"${deploy_args[@]}"
