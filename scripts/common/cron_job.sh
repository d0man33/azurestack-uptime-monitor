#!/bin/bash

echo "=========== Job arguments"
JOB_NAME=$1
JOB_SCRIPT=$2
JOB_TIMESTAMP=$(date --utc +%s)

function azs_existing_service_remove
{
    # Is there an existing service?
    sudo docker service inspect $JOB_NAME > /dev/null \
      && echo "Service ${JOB_NAME} exists" \
      || { echo "There is no service with the name ${JOB_NAME}" ; return 0 ; }

    # Export log from the existing service task
    sudo docker container logs \
          $(sudo docker container ls -a --filter name=$JOB_NAME --format "{{.ID}}") \
          > /azs/cli/log/${JOB_NAME}.log \
      && echo "Exported log from docker service" \
      || echo "Unable to export log from docker service"

    # Get the timestamp from the existing serivce 
    local EXISTING_SERVICE_TIMESTAMP=$(( $(sudo docker service inspect $JOB_NAME --format='{{.Spec.Labels.timestamp}}')/1000000000)) \
      && echo "Retrieved timestamp from existing service" \
      || echo "Unable to retrieve timestamp from existing service"

    # Check if existing serivce task is still running 
    local EXISTING_SERVICE_TASK_STATUS=$(sudo docker service ps $JOB_NAME --format "{{.CurrentState}}") \
      && echo "Retrieved Docker Service task status" \
      || echo "Unable to retrieve Docker Service task status"

    # If existing service task is still running, update record in DB (based on existing TIMESTAMP)
    [[ $EXISTING_SERVICE_TASK_STATUS == Running* ]] \
      && curl -s -i -XPOST "http://localhost:8086/write?db=azs&precision=s" --data-binary "${JOB_NAME} status=\"exceeded_max_runtime\",job_runtime=$(( $JOB_TIMESTAMP-$EXISTING_SERVICE_TIMESTAMP )) $EXISTING_SERVICE_TIMESTAMP" | grep HTTP \
      || echo "Service task has exited"

    # Remove the existing service
    sudo docker service rm $JOB_NAME \
    && echo "Removed existing service" \
    || { echo "Unable to remove the existing service" ; return 1 ; }
    
    return 0
}

azs_existing_service_remove
# If the function exits with a 1, then the service exists but is not removed.
# IF [ $? = 1 ] then notify?

AZURECLI_VERSION=$(sudo cat /azs/common/config.json | jq -r ".version.azurecli") \
  && echo "## Pass: retrieve azurecli version from config" \
  || { echo "## Fail: retrieve azurecli version from config" ; exit 1 ; }

# Create new service and add a new record in the DB (with current JOB_TIMESTAMP)
sudo docker service create \
     --name $JOB_NAME \
     --label timestamp=$JOB_TIMESTAMP \
     --detach \
     --restart-condition none \
     --network="azs" \
     --mount type=bind,src=/azs/cli,dst=/azs/cli \
     --env JOB_NAME=$JOB_NAME \
     --env JOB_TIMESTAMP=$JOB_TIMESTAMP \
     --secret cli \
     microsoft/azure-cli:$AZURECLI_VERSION \
     $JOB_SCRIPT \
  && curl -s -i -XPOST "http://localhost:8086/write?db=azs&precision=s" --data-binary "${JOB_NAME} job=0,status=\"docker_service_created\" ${JOB_TIMESTAMP}" | grep HTTP \
  || echo "Unable to create docker service"