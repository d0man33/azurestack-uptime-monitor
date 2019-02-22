#!/bin/bash

JOB_NAME=debug_azurecli
JOB_TIMESTAMP=$(date --utc +%s)

# Remove existing service

SERVICEID=$(sudo docker service ls --filter name=$JOB_NAME --format "{{.ID}}")

if ! [ -z "$SERVICEID" ]
then
  sudo docker service rm $SERVICEID \
    && echo "## Pass: remove existing docker service" \
    || echo "## Pass: no exisiting docker service found"
fi

# Wait for container to cleaned up
Y=20
while [ $Y -ge 1 ]
do
  CONTAINERID=$(sudo docker container ls -a --filter name=$JOB_NAME --format "{{.ID}}")
  echo $CONTAINERID
  if [ -z "$CONTAINERID" ]; then break; fi
  echo "Waiting for container to be cleaned up. $Y seconds"
  sleep 1s
  Y=$(( $Y - 1 ))
  if [ $Y = 0 ]; then { echo "## Fail: debug_azurecli container not cleaned up" ; return 1 ; }; fi
done

# Get Azure CLI docker image version
AZURECLI_VERSION=$(sudo cat /azs/common/config.json | jq -r ".version.azurecli") \
  && echo "## Pass: retrieve azurecli version from config" \
  || { echo "## Fail: retrieve azurecli version from config" ; return 1 ; }

# Azure CLI
sudo docker service create \
     --name $JOB_NAME \
     --label timestamp=$JOB_TIMESTAMP \
     --detach \
     -t \
     --restart-condition none \
     --network azs \
     --mount type=bind,src=/azs/cli,dst=/azs/cli \
     --env JOB_NAME=$JOB_NAME \
     --env JOB_TIMESTAMP=$JOB_TIMESTAMP \
     --secret cli \
     microsoft/azure-cli:$AZURECLI_VERSION \
     /bin/bash 

# Wait for container to start
Y=15
while [ $Y -ge 1 ]
do
  CONTAINERID=$(sudo docker container ls -a --filter name=$JOB_NAME --format "{{.ID}}")
  echo $CONTAINERID
  if ! [ -z "$CONTAINERID" ]; then break; fi
  echo "Waiting for container to start. $Y seconds"
  sleep 1s
  Y=$(( $Y - 1 ))
  if [ $Y = 0 ]; then { echo "## Fail: debug_azurecli container did not start" ; return 1 ; }; fi
done

# Exec to the VM
sudo docker exec -it $(sudo docker container ls -a --filter name=$JOB_NAME --format "{{.ID}}") /bin/bash
