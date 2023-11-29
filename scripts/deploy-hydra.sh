#!/bin/bash

if [ $# -lt 2 ]
  then
    echo "Usage: ./deploy-hydra.sh <admin|public> <development|staging|production>"
    exit 1
fi

hydra_service=$1
env=$2
service_name="ory-hydra-${hydra_service}-${env}"
dockerfile="Dockerfile-${hydra_service}"
image_name="gcr.io/corsali-${env}/ory-hydra-${hydra_service}"

echo "Setting up doppler"
doppler setup --project vana-oauth --config ${env}
doppler secrets download --no-file --format env > .env
export $(cat .env | xargs)

echo "Creating hydra.yml"
envsubst < hydra.template.yml > hydra.yml
unset $(cat .env | cut -d= -f1 | xargs)
rm .env

echo "Configuring gcloud"
gcloud config set project corsali-${env}

echo "Build and push docker image"
docker build --no-cache --platform linux/amd64 -t ${image_name} -f docker/${dockerfile} .
docker push ${image_name}

echo "Deploy to Cloud Run"
gcloud container images describe ${image_name}
gcloud run deploy ${service_name} \
    --image ${image_name} \
    --region us-central1 \
    --vpc-connector vpc-conn-${env} \
    --allow-unauthenticated
