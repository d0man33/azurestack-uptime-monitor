#!/bin/bash

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

BASE_URL=https://raw.githubusercontent.com/d0man33/azurestack-uptime-monitor/master

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