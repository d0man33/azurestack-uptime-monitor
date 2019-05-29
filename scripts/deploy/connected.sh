#!/bin/bash

ARGUMENTS_JSON=$1
ARGUMENTS_BLOB_ENDPOINT=$2

########################### Install Prereqs ###################################
echo "##################### Install Prereqs"

sudo apt-get update \
  && echo "## Pass: updated package database" \
  || { echo "## Fail: failed to update package database" ; exit 1 ; }

sudo apt-get install -y apt-transport-https lsb-release ca-certificates curl software-properties-common dirmngr jq \
  && echo "## Pass: prereq packages installed" \
  || { echo "## Fail: failed to install prereq packages" ; exit 1 ; }

sudo apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv \
     --keyserver packages.microsoft.com \
     --recv-keys BC528686B50D79E339D3721CEB3E94ADBE1229CF \
  && echo "## Pass: added Microsoft signing key for CLI repository" \
  || { echo "## Fail: failed to add Microsoft signing key for CLI repository" ; exit 1 ; }

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - \
  && echo "## Pass: added GPG key for Docker repository" \
  || { echo "## Fail: failed to add GPG key for Docker repository" ; exit 1 ; }

AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list \
  && echo "## Pass: added CLI repository to APT sources" \
  || { echo "## Fail: failed to add CLI repository to APT sources" ; exit 1 ; }

sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  && echo "## Pass: added Docker repository to APT sources" \
  || { echo "## Fail: failed to add Docker repository to APT sources" ; exit 1 ; }

sudo apt-get update \
  && echo "## Pass: updated package database with Docker packages" \
  || { echo "## Fail: failed to update package database with Docker packages" ; exit 1 ; }

sudo apt-get install azure-cli \
  && echo "## Pass: installed azure cli" \
  || { echo "## Fail: failed to install azure cli" ; exit 1 ; }

sudo apt-get install -y docker-ce \
  && echo "## Pass: installed docker-ce" \
  || { echo "## Fail: failed to install docker-ce" ; exit 1 ; }

# Files

sudo mkdir -p /azs/{influxdb,grafana/{database,datasources,dashboards},common,cli/{jobs,shared,export,log},deploy} \
  && echo "## Pass: created directory structure" \
  || { echo "## Fail: failed to create directory structure" ; exit 1 ; }

BASE_URL=https://raw.githubusercontent.com/Azure/azurestack-uptime-monitor/master

FILE=$(sudo curl -s "$BASE_URL"/scripts/common/config.json | jq -r ".files[] | .[]") \
  && echo "## Pass: retrieve file json" \
  || { echo "## Fail: retrieve file json" ; exit 1 ; }

for i in $FILE
do
  sudo curl -s "$BASE_URL"/scripts"$i" --output /azs"$i" \
    && echo "## Pass: downloaded $BASE_URL/scripts$i to /azs$i" \
    || { echo "## Fail: failed to download $BASE_URL/scripts$i to /azs$i" ; exit 1 ; }
done

# Docker images

INFLUXDB_VERSION=$(sudo cat /azs/common/config.json | jq -r ".version.influxdb") \
  && echo "## Pass: retrieve influxdb version from config" \
  || { echo "## Fail: retrieve influxdb version from config" ; exit 1 ; }

GRAFANA_VERSION=$(sudo cat /azs/common/config.json | jq -r ".version.grafana") \
  && echo "## Pass: retrieve grafana version from config" \
  || { echo "## Fail: retrieve grafana version from config" ; exit 1 ; }

AZURECLI_VERSION=$(sudo cat /azs/common/config.json | jq -r ".version.azurecli") \
  && echo "## Pass: retrieve azurecli version from config" \
  || { echo "## Fail: retrieve azurecli version from config" ; exit 1 ; }

sudo docker pull influxdb:$INFLUXDB_VERSION \
  && echo "## Pass: pulled influxdb image from docker hub" \
  || { echo "## Fail: failed to pull influxdb image from docker hub" ; exit 1 ; }

sudo docker pull grafana/grafana:$GRAFANA_VERSION \
  && echo "## Pass: pulled grafana image from docker hub" \
  || { echo "## Fail: failed to pull grafana image from docker hub" ; exit 1 ; }

sudo docker pull microsoft/azure-cli:$AZURECLI_VERSION  \
  && echo "## Pass: pulled microsoft/azure-cli image from docker hub" \
  || { echo "## Fail: failed to pull microsoft/azure-cli image from docker hub" ; exit 1 ; }

########################### Registration ######################################
echo "##################### Registration"

  # Set to Azure Cloud first to cleanup a profile from failed deployments
  az cloud set \
    --name AzureCloud \
  && echo "## Pass: select AzureCloud" \
  || { echo "## Fail: select cloud" ; exit 1 ; }

  # Cleanup existing profile from failed deployment
  az cloud unregister \
      --name AzureStackCloud \
  && echo "## Pass: unregister AzureStackCloud" \
  || echo "## Pass: AzureStackCloud does not exist yet" 

source /azs/cli/shared/functions.sh \
  && echo "## Pass: Source functions.sh" \
  || { echo "## Fail:  Source functions.sh" ; exit 1 ; }

azs_registration

########################### Configure #########################################
echo "##################### Configure"

# Variables

FQDN=${ARGUMENTS_BLOB_ENDPOINT#*.} \
  && echo "## Pass: remove storageaccountname. from blob endpoint" \
  || { echo "## Fail: remove storageaccountname. from blob endpoint" ; exit 1 ; }

FQDN=${FQDN#*.} \
  && echo "## Pass: remove blob. from blob endpoint" \
  || { echo "## Fail: remove blob. from blob endpoint" ; exit 1 ; }

FQDN=${FQDN%/*} \
  && echo "## Pass: remove trailing backslash from blob endpoint" \
  || { echo "## Fail: remove trailing backslash from blob endpoint" ; exit 1 ; }

API_PROFILE=$(echo $ARGUMENTS_JSON | jq -r ".apiProfile") \
  && echo "## Pass: set variable API_PROFILE" \
  || { echo "## Fail: set variable API_PROFILE" ; exit 1 ; }

TENANT_ID=$(echo $ARGUMENTS_JSON | jq -r ".tenantId") \
  && echo "## Pass: set variable TENANT_ID" \
  || { echo "## Fail: set variable TENANT_ID" ; exit 1 ; }

APP_ID=$(echo $ARGUMENTS_JSON | jq -r ".appId") \
  && echo "## Pass: set variable APP_ID" \
  || { echo "## Fail: set variable APP_ID" ; exit 1 ; }

APP_KEY=$(echo $ARGUMENTS_JSON | jq -r ".appKey") \
  && echo "## Pass: set variable APP_KEY" \
  || { echo "## Fail: set variable APP_KEY" ; exit 1 ; }

SUBSCRIPTION_ID=$(echo $ARGUMENTS_JSON | jq -r ".tenantSubscriptionId") \
  && echo "## Pass: set variable SUBSCRIPTION_ID" \
  || { echo "## Fail: set variable SUBSCRIPTION_ID" ; exit 1 ; }

LOCATION=$(echo $ARGUMENTS_JSON | jq -r ".location") \
  && echo "## Pass: set variable LOCATION" \
  || { echo "## Fail: set variable LOCATION" ; exit 1 ; }

UNIQUE_STRING=$(echo $ARGUMENTS_JSON | jq -r ".uniqueString") \
  && echo "## Pass: set variable UNIQUE_STRING" \
  || { echo "## Fail: set variable UNIQUE_STRING" ; exit 1 ; }

ADMIN_USERNAME=$(echo $ARGUMENTS_JSON | jq -r ".adminUsername") \
  && echo "## Pass: set variable ADMIN_USERNAME" \
  || { echo "## Fail: set variable ADMIN_USERNAME" ; exit 1 ; }

# Certificates

sudo cat /etc/ssl/certs/ca-certificates.crt \
      | sudo tee /azs/cli/shared/ca-bundle.crt > /dev/null \
  && echo "## Pass: copy the ca-certificates bundle" \
  || { echo "## Fail: copy the ca-certificates bundle" ; exit 1 ; }

sudo cat /var/lib/waagent/Certificates.pem \
      | sudo tee -a /azs/cli/shared/ca-bundle.crt > /dev/null \
  && echo "## Pass: append the waagent cert to the ca bundle" \
  || { echo "## Fail: append the waagent cert to the ca bundle" ; exit 1 ; }

# Permissions

sudo chmod -R 755 /azs/{common,cli/{jobs,shared,export}} \
  && echo "## Pass: set execute permissions for directories" \
  || { echo "## Fail: set execute permissions for directories" ; exit 1 ; }

sudo chmod -R 777 /azs/cli/log \
  && echo "## Pass: set write permissions for directory" \
  || { echo "## Fail: set write permissions for directory" ; exit 1 ; }

########################### Function az login and logout ######################
echo "##################### Function az login and logout"

function azs_login
{
  local FQDNHOST=$1

  export REQUESTS_CA_BUNDLE=/azs/cli/shared/ca-bundle.crt \
    && echo "## Pass: set REQUESTS_CA_BUNDLE with ca bundle" \
    || { echo "## Fail: set REQUESTS_CA_BUNDLE with ca bundle" ; exit 1 ; }

  az cloud register \
      --name AzureStackCloud \
      --endpoint-resource-manager "https://$FQDNHOST.$FQDN" \
      --suffix-storage-endpoint $FQDN \
      --profile $API_PROFILE \
    && echo "## Pass: register cloud" \
    || { echo "## Fail: register cloud" ; exit 1 ; }

  ## Select cloud
  az cloud set \
      --name AzureStackCloud \
    && echo "## Pass: select cloud" \
    || { echo "## Fail: select cloud" ; exit 1 ; }

  ## Sign in as SPN
  az login \
        --service-principal \
        --tenant $TENANT_ID \
        --username $APP_ID \
        --password $APP_KEY \
    && echo "## Pass: signin as service principal" \
    || { echo "## Fail: signin as service principal" ; exit 1 ; }

  ## If auth endpoint is management, then set tenantSubscriptionId for SPN
  if [ "$FQDNHOST" = "management" ]
  then
    az account set \
          --subscription $SUBSCRIPTION_ID \
      && echo "## Pass: set subscription id" \
      || { echo "## Fail: set subscription id" ; exit 1 ; }
  fi

  return 0
}

function azs_logout 
{
  az logout \
    && echo "## Pass: az logout" \
    || { echo "## Fail: az logout" ; exit 1 ; }

  az cloud set \
      --name AzureCloud \
    && echo "## Pass: select cloud" \
    || { echo "## Fail: select cloud" ; exit 1 ; }

  az cloud unregister \
        --name AzureStackCloud \
    && echo "## Pass: unregister AzureStackCloud" \
    || { echo "## Fail: unregister AzureStackCloud" ; exit 1 ; }

  return 0
}

########################### Provision Test Resources ##########################
echo "##################### Provision Test Resources"

azs_login management

az group create \
  --location $LOCATION \
  --name $UNIQUE_STRING \
  && echo "## Pass: create resource group" \
  || { echo "## Fail: create resource group" ; exit 1 ; }

az group deployment create \
  --resource-group $UNIQUE_STRING \
  --name bootstrap \
  --template-file /azs/cli/shared/mainTemplate.json \
  --parameters uniqueString=$UNIQUE_STRING \
  && echo "## Pass: deploy template" \
  || { echo "## Fail: deploy template" ; exit 1 ; }

UNIQUE_STRING_STORAGE_ACCOUNT="$UNIQUE_STRING"storage \
  && echo "## Pass: set variable UNIQUE_STRING_STORAGE_ACCOUNT" \
  || { echo "## Fail: set variable UNIQUE_STRING_STORAGE_ACCOUNT" ; exit 1 ; }

UNIQUE_STRING_STORAGE_ACCOUNT_KEY=$(az storage account keys list \
        --account-name $UNIQUE_STRING_STORAGE_ACCOUNT \
        --resource-group $UNIQUE_STRING \
        | jq -r ".[0].value") \
  && echo "## Pass: retrieve storage account key" \
  || { echo "## Fail: retrieve storage account key" ; exit 1 ; }

az storage container create \
        --name $UNIQUE_STRING \
        --account-name $UNIQUE_STRING_STORAGE_ACCOUNT \
        --account-key $UNIQUE_STRING_STORAGE_ACCOUNT_KEY \
        --public-access blob \
  && echo "## Pass: create container" \
  || { echo "## Fail: create container" ; exit 1 ; }

echo $UNIQUE_STRING > read.log \
  && echo "## Pass: create read.log" \
  || { echo "## Fail: create read.log" ; exit 1 ; }

az storage blob upload \
        --container-name $UNIQUE_STRING \
        --account-name $UNIQUE_STRING_STORAGE_ACCOUNT \
        --account-key $UNIQUE_STRING_STORAGE_ACCOUNT_KEY \
        --file read.log \
        --name read.log \
  && echo "## Pass: upload blob" \
  || { echo "## Fail: upload blob" ; exit 1 ; }

azs_logout

########################### Azure Bridge SubscriptionId #######################
echo "##################### Azure Bridge SubscriptionId"

azs_login adminmanagement

function azs_bridge
{
  BRIDGE_ACTIVATION_ID=$(az resource list \
        --resource-type "Microsoft.AzureBridge.Admin/activations" \
        | jq -r ".[0].id") \
    && echo "## Pass: get activation id" \
    || { echo "## Fail: get activation id" ; exit 1 ; }

  if [ $BRIDGE_ACTIVATION_ID = "null" ]
  then
    echo "## Pass: Azure Stack not registered"
    BRIDGE_SUBSCRIPTION_ID="azurestacknotregistered"
    return 0
  fi

  BRIDGE_REGISTRATION_ID=$(az resource show \
        --ids $BRIDGE_ACTIVATION_ID \
        | jq -r ".properties.azureRegistrationResourceIdentifier") \
    && echo "## Pass: get registration id" \
    || { echo "## Fail: get registration id" ; exit 1 ; }

  # Remove leading "/"
  BRIDGE_SUBSCRIPTION_ID=${BRIDGE_REGISTRATION_ID#*/} \
    && echo "## Pass: remove leading /" \
    || { echo "## Fail: remove leading /" ; exit 1 ; }

  # Remove "sbscriptions/"
  BRIDGE_SUBSCRIPTION_ID=${BRIDGE_SUBSCRIPTION_ID#*/} \
    && echo "## Pass: remove subscriptions/" \
    || { echo "## Fail: remove subscriptions/" ; exit 1 ; }

  # Remove trailing path from subscription id
  BRIDGE_SUBSCRIPTION_ID=${BRIDGE_SUBSCRIPTION_ID%%/*} \
    && echo "## Pass: remove trailing path from subscription id" \
    || { echo "## Fail: remove trailing path from subscription id" ; exit 1 ; }
}

azs_bridge

azs_logout

########################### Remove Existing Services ##########################
echo "##################### Remove Existing Services"

sudo docker swarm init \
  && echo "## Pass: initialize Docker Swarm" \
  || echo "## Pass: Docker Swarm is already initialized"

sudo crontab -u $ADMIN_USERNAME -r \
  && echo "## Pass: remove existing crontab for $ADMIN_USERNAME" \
  || echo "## Pass: crontab is not yet configured for $ADMIN_USERNAME"

sudo docker service rm $(sudo docker service ls --format "{{.ID}}") \
  && echo "## Pass: removed existing docker services" \
  || echo "## Pass: no exisiting docker service found"
    
sudo docker secret rm $(sudo docker secret ls --format "{{.ID}}") \
  && echo "## Pass: removed existing docker secrets" \
  || echo "## Pass: no exisiting docker secret found"

########################### Create Services ###################################
echo "##################### Create Services"

sudo docker network create --driver overlay azs \
  && echo "## Pass: create network overlay azs" \
  || echo "## Pass: network overlay azs already exists"

ARGUMENTS_JSON=$(echo $ARGUMENTS_JSON \
      | jq --arg X $FQDN '. + {fqdn: $X}') \
  && echo "## Pass: add fqdn" \
  || { echo "## Fail: add fqdn" ; exit 1 ; }

ARGUMENTS_JSON=$(echo $ARGUMENTS_JSON \
      | jq --arg X $BRIDGE_SUBSCRIPTION_ID '. + {azureSubscriptionId: $X}') \
  && echo "## Pass: add azureSubscriptionId" \
  || { echo "## Fail: add azureSubscriptionId" ; exit 1 ; }

ARGUMENTS_JSON=$(echo $ARGUMENTS_JSON \
      | jq --arg X $(sudo cat /azs/common/config.json | jq -r ".version.script") '. + {scriptVersion: $X}') \
  && echo "## Pass: add fqdn" \
  || { echo "## Fail: add fqdn" ; exit 1 ; }

echo $ARGUMENTS_JSON | sudo docker secret create cli - \
  && echo "## Pass: created docker secret cli" \
  || { echo "## Fail: created docker secret cli" ; exit 1 ; }

# InfluxDB
sudo docker service create \
     --name influxdb \
     --detach \
     --restart-condition any \
     --network azs \
     --mount type=bind,src=/azs/influxdb,dst=/var/lib/influxdb \
     --publish published=8086,target=8086 \
     --env INFLUXDB_DB=azs \
     influxdb:$INFLUXDB_VERSION \
  && echo "## Pass: create docker service for influxdb" \
  || { echo "## Fail: create docker service for influxdb" ; exit 1 ; }

# Grafana
sudo docker service create \
     --name grafana \
     --detach \
     --restart-condition any \
     --network azs \
     --user $(sudo id -u) \
     --mount type=bind,src=/azs/grafana/database,dst=/var/lib/grafana \
     --mount type=bind,src=/azs/grafana/datasources,dst=/etc/grafana/provisioning/datasources \
     --mount type=bind,src=/azs/grafana/dashboards,dst=/etc/grafana/provisioning/dashboards \
     --publish published=443,target=443 \
     --env GF_SECURITY_ADMIN_USER=$(echo $ARGUMENTS_JSON | jq -r ".adminUsername") \
     --env GF_SECURITY_ADMIN_PASSWORD=$(echo $ARGUMENTS_JSON | jq -r ".grafanaPassword") \
     grafana/grafana:$GRAFANA_VERSION \
  && echo "## Pass: create docker service for grafana" \
  || { echo "## Fail: create docker service for grafana" ; exit 1 ; }

# Wait for InfluxDB http api to respond
X=15
while [ $X -ge 1 ]
do
  curl -s "http://localhost:8086/ping"
  if [ $? = 0 ]; then break; fi
  echo "Waiting for influxdb http api to respond. $X seconds"
  sleep 1s
  X=$(( $X - 1 ))
  if [ $X = 0 ]; then { echo "## Fail: influxdb http api not responding" ; exit 1 ; }; fi
done

# Crontab
sudo crontab -u $ADMIN_USERNAME /azs/common/cron_tab.conf \
  && echo "## Pass: create crontab for $ADMIN_USERNAME" \
  || { echo "## Fail: create crontab for $ADMIN_USERNAME" ; exit 1 ; }

# InfluxDB retention policy
curl -sX POST "http://localhost:8086/query?db=azs" \
      --data-urlencode "q=CREATE RETENTION POLICY "azs_90days" ON "azs" DURATION 90d REPLICATION 1 SHARD DURATION 7d DEFAULT" \
  && echo "## Pass: set retention policy to 90 days" \
  || { echo "## Fail: set retention policy to 90 days" ; exit 1 ; }