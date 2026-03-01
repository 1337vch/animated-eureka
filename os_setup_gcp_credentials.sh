#!/bin/bash
set -e

# Check for gcloud and install if not present
if ! command -v gcloud &> /dev/null
then
    echo "gcloud not found. Installing Google Cloud SDK..."
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    sudo apt-get install -y apt-transport-https ca-certificates gnupg
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    sudo apt-get update && sudo apt-get install -y google-cloud-sdk
    echo "gcloud installed successfully."
fi

PROJECT_ID="neon-webbing-488720-e6"
SERVICE_ACCOUNT_NAME="zorin-image-builder"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="zorin-builder-key.json"

echo "Creating service account..."
gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${PROJECT_ID}" \
    --description="Service account for building Zorin OS images" \
    --display-name="Zorin Image Builder" || echo "Service account already exists."

echo "Granting Storage Admin role..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/storage.admin"

echo "Granting Compute Admin role..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/compute.admin"

echo "Creating and downloading service account key..."
gcloud iam service-accounts keys create "${KEY_FILE}" \
    --iam-account="${SERVICE_ACCOUNT_EMAIL}"

echo ""
echo "Credential setup complete."
echo ""
echo "On your external machine, you now need to set the GOOGLE_APPLICATION_CREDENTIALS environment variable."
echo "Use the following command:"
echo ""
echo "export GOOGLE_APPLICATION_CREDENTIALS=\"\$(pwd)/${KEY_FILE}\""
echo ""
echo "After setting the environment variable, you can run the gce-image-build.sh script."
