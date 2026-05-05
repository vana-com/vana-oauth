#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: ./scripts/migrate-hydra.sh <development|production>" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

env=$1
case "$env" in
  development|production) ;;
  *) usage ;;
esac

HYDRA_VERSION="${HYDRA_VERSION:-v26.2.0}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "$repo_root"

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

echo "Running Hydra SQL migrations with oryd/hydra:${HYDRA_VERSION}"
docker run --rm --platform linux/amd64 \
  -e DSN="$DATABASE_URL" \
  -v "$hydra_config:/etc/config/hydra/hydra.yml:ro" \
  "oryd/hydra:${HYDRA_VERSION}" \
  migrate sql up -e --yes --config /etc/config/hydra/hydra.yml
