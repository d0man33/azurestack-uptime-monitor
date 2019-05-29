# Connected version of the Azure Stack uptime monitor 

This procedure requires outbound connectivity for the solution VM. On average the deployment will take ~15 minutes.

## Prerequisites
The connected version has the following prerequisites.

- Outbound internet connectivity for virtual machines running on Azure Stack.
- Ubuntu image (18.04-LTS or 16.04-LTS) downloaded from the Azure marketplace feed in Azure Stack marketplace management.
- The **Custom Script for Linux v2.0** downloaded from the Azure marketplace feed in Azure Stack marketplace management.
- A tenant user in the same tenant as the SPN account that has at least **contributor** permissions to a resource group that the solution will be deployed to.
- An SPN created in the Identity Provider ([AAD](https://docs.microsoft.com/en-us/azure/azure-stack/user/azure-stack-create-service-principals#create-service-principal-for-azure-ad) or [ADFS](https://docs.microsoft.com/en-us/azure/azure-stack/azure-stack-create-service-principals#create-a-service-principal-using-a-client-secret)). The authentication method for the SPN account must be with a key (certificate based authentication is not supported). The SPN must have **reader** permissions on the Azure Stack default provider subscription and **contributor** permissions on an Azure Stack tenant subscription.
- An SSH key pair for authenticating to the solution VM. [Guide for creating and using the ssh key pair](/docs/SSH.md).

## Deploy

Login to the Azure Stack tenant portal with a user that has access contributor access on the subscription you want to deploy the solution into. Select to create a new resource and search for **template deployment** in the marketplace. Select **edit template** and copy the [connected - deployment template](https://raw.githubusercontent.com/d0man33/azurestack-uptime-monitor/master/deploy/connected/mainTemplate.json) to template editor and hit save.

The deployment template requires the following inputs:

- activationKey: the activation key can be acquired by [request](https://github.com/Azure/azurestack-uptime-monitor/issues/new?assignees=&labels=&template=request-activation-key.md&title=Please+provide+me+with+an+activation+key) on this repository.
- adminUserName: the username is used for authenticating to the Linux VM.
- sshPublicKey: the SSH public key is inserted into the Linux VM. Once you authenticate with your private key stored on you local machine signin will be granted. Without the private key on your machine you cannot connect to the VM. With the proper permissions Azure Stack allows you to reset SSH public in the VM (in case you lose you're private key)
- appId: this is the application Id of the SPN created in the identity store.
- appKey: this is the key (password) for the SPN created in the identity store.
- grafanaPassword: this password is used to authenticate to the Grafana portal, once the deployment is completed.

The deployment template also provides the following optional inputs:
- ubuntuSku: if a value for this parameter is not specified, the default value of 18.04-LTS will be used. Alternatively you can specify 16.04-LTS as input value. No other input values are allowed
- triggerdId: This value is only relevant for updating the solution. The solution is updating by deploying the same to the same resource group with existing resources from an earlier deployment. If the environment is deployed for the first time, the Linux VM extension is triggered automatically. On subsequent deployments to the same resource group with the existing resources, the Linux VM extension is not executed by default. By specifying a different value for the triggerId the Linux VM extension executes again (as long as the triggerId has a different value than the previous deployment). The default value of the triggerId is 1. It accepts any value between 1 and 100.

## Update