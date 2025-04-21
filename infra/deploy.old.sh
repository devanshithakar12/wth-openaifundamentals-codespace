#!/bin/bash
# Include functions
source ./functions.sh
# Parse arguments

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --subscription-id) SUBSCRIPTION_ID="$2"; shift ;;
        --resource-group-name) RESOURCE_GROUP_NAME="$2"; shift ;;
        --location) LOCATION="$2"; shift ;;
        --tenant-id) TENANT_ID="$2"; shift ;;
        --use-service-principal) USE_SERVICE_PRINCIPAL=true ;;
        --service-principal-id) SERVICE_PRINCIPAL_ID="$2"; shift ;;
        --service-principal-password) SERVICE_PRINCIPAL_PASSWORD="$2"; shift ;;
        --openai-location) OPENAI_LOCATION="$2"; shift ;;
        --document-intelligence-location) DOCUMENT_INTELLIGENCE_LOCATION="$2"; shift ;;
        --ai-foundry-hub-name) AI_FOUNDRY_HUB_NAME="$2"; shift ;;
        --ai-foundry-hub-friendly_name) AI_FOUNDRY_HUB_FRIENDLY_NAME="$2"; shift ;;
        --ai-foundry-hub-description) AI_FOUNDRY_HUB_DESCRIPTION="$2"; shift ;;
        --ai-foundry-project-name) AI_FOUNDRY_PROJECT_NAME="$2"; shift ;;
        --search-service-name) SEARCH_SERVICE_NAME="$2"; shift ;;
        *) error_exit "Unknown parameter passed: $1" ;;
    esac
    shift
done

# Variables
declare -A variables=(
  [template]="main.bicep"
  [parameters]="main.bicepparam"
  [resourceGroupName]="rg-ai-foundry-secure"
  [location]="eastus"
  [validateTemplate]=0
  [useWhatIf]=0
)
# Validate mandatory parameters
if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP_NAME" || -z "$AI_FOUNDRY_HUB_NAME" || -z "$AI_FOUNDRY_PROJECT_NAME" || -z "$SEARCH_SERVICE_NAME" ]]; then
    error_exit "Subscription ID, Resource Group Name, AI Foundry Hub Name, AI Foundry Project Name, and Search Service Name are mandatory."
fi

# Check if Bicep CLI is installed
if ! command -v az bicep &> /dev/null; then
    error_exit "Bicep CLI not found. Install it using 'az bicep install'."
fi

# Default values
LOCATION="East US 2"
DOCUMENT_INTELLIGENCE_LOCATION="East US"
OPENAI_LOCATION="East US 2"
SEARCH_SKU="basic"

# Create resource group
echo -e "\n- Creating resource group: "
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" || error_exit "Failed to create resource group."

# Authenticate with Azure
if [[ "$USE_SERVICE_PRINCIPAL" == true ]]; then  
    if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP_NAME" || -z "$AI_FOUNDRY_HUB_NAME" || -z "$AI_FOUNDRY_PROJECT_NAME" || -z "$SEARCH_SERVICE_NAME" || -z "$TENANT_ID" ]]; then
        error_exit "Subscription ID, Resource Group Name, AI Foundry Hub Name, AI Foundry Project Name, Tenant ID, and Search Service Name are mandatory."
    fi
    az login --service-principal -u "$SERVICE_PRINCIPAL_ID" -p "$SERVICE_PRINCIPAL_PASSWORD" --tenant "$TENANT_ID" || error_exit "Failed to authenticate using Service Principal."
else
    az login --use-device-code|| error_exit "Failed to authenticate with Azure."
fi

# Set the subscription
az account set --subscription "$SUBSCRIPTION_ID" || error_exit "Failed to set subscription."

# Display deployment parameters
echo -e "The resources will be provisioned using the following parameters:"
echo -e "\t          TenantId: \e[33m$TENANT_ID\e[0m"
echo -e "\t    SubscriptionId: \e[33m$SUBSCRIPTION_ID\e[0m"
echo -e "\t    Resource Group: \e[33m$RESOURCE_GROUP_NAME\e[0m"
echo -e "\t            Region: \e[33m$LOCATION\e[0m"
echo -e "\t   OpenAI Location: \e[33m$OPENAI_LOCATION\e[0m"
echo -e "\t Azure DI Location: \e[33m$DOCUMENT_INTELLIGENCE_LOCATION\e[0m"
echo -e "\e[31mIf any parameter is incorrect, abort this script, correct, and try again.\e[0m"
echo -e "It will take around \e[32m15 minutes\e[0m to deploy all resources. You can monitor the progress from the deployments page in the resource group in Azure Portal.\n"

read -p "Press Y to proceed to deploy the resources using these parameters: " proceed
if [[ "$proceed" != "Y" ]]; then
    echo -e "\e[31mAborting deployment script.\e[0m"
    exit 1
fi

start=$(date +%s)


# Deploy Bicep template
echo "Deploying resources..."
az deployment group create \
  --resource-group $RESOURCE_GROUP_NAME \
  --template-file main.bicep \
  --parameters \
    location="$LOCATION" \
    aiHubName="$AI_FOUNDRY_HUB_NAME" \
    aiHubFriendlyName="$AI_FOUNDRY_HUB_FRIENDLY_NAME" \
    aiHubDescription="$AI_FOUNDRY_HUB_DESCRIPTION" \
    aiFoundryProjectName="$AI_FOUNDRY_PROJECT_NAME" \
    searchServiceName="$SEARCH_SERVICE_NAME" \
    searchSku="$SEARCH_SKU"

# Extract outputs
outputs=$(echo "$result" | jq -r '.properties.outputs')

# Create settings file
echo -e "\n- Creating the .env file:"
environment_file="../.env"
environment_sample_file="../.env.sample"

if [[ ! -f "$environment_sample_file" ]]; then
    error_exit "Example .env.sample file not found at $environment_sample_file."
fi
# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error_exit "jq not found. Install it using 'sudo apt-get install jq'."
fi
# Populate .env file
# jq --arg openAIKey "$(echo "$outputs" | jq -r '.openAIKey.value')" \
#    --arg openAIEndpoint "$(echo "$outputs" | jq -r '.openAIEndpoint.value')" \
#    --arg searchKey "$(echo "$outputs" | jq -r '.searchKey.value')" \
#    --arg searchEndpoint "$(echo "$outputs" | jq -r '.searchEndpoint.value')" \
#    --arg documentEndpoint "$(echo "$outputs" | jq -r '.documentEndpoint.value')" \
#    --arg documentKey "$(echo "$outputs" | jq -r '.documentKey.value')" \
#    '.Values.AZURE_OPENAI_API_KEY = $openAIKey |
#     .Values.AZURE_OPENAI_ENDPOINT = $openAIEndpoint |
#     .Values.AZURE_AI_SEARCH_ADMIN_KEY = $searchKey |
#     .Values.AZURE_AI_SEARCH_ENDPOINT = $searchEndpoint |
#     .Values.DOCUMENT_INTELLIGENCE_ENDPOINT = $documentEndpoint |
#     .Values.DOCUMENT_INTELLIGENCE_KEY = $documentKey' \
#    "$environment_sample_file" > tmp.json && mv tmp.json "$environment_file"
echo $outputs

echo -e "\e[32m.env file created successfully.\e[0m"

end=$(date +%s)
echo -e "\nThe deployment took: $((end - start)) seconds."