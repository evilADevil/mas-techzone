#!/bin/bash
## Check if we are logged in something
echo "+------------------------------+"
echo "| Script to install MAS Manage |"
echo "+------------------------------+"
CLUSTER=$(oc status >/dev/null 2>/dev/null)
if [ $? -eq 1 ]
then
  echo "You don't seem to be logged to a cluster."
  echo "Use \"oc login\" to login to a custer and then restart this script."
  exit 1
else
  CLUSTER=$(oc status | grep 'on server' | awk '{print $6}')
  echo "Cluster to use: $CLUSTER"
  ls -f license.dat >/dev/null 2>/dev/null
  if [ $? -ne 0 ]
  then
	echo "Cannot find license.dat in the current directory. Aborting."
	exit 1  
  fi
  read -p "Press Return to continue... on Ctrl-C to abort."
fi
## Creates a pod to run the MAS ansible collection
echo "Creating a pod to run the MAS Ansible collection from within the cluster."
oc apply -f masdevops.yaml
oc project mas-devops
POD=$(oc get pods | grep -i mas-devops-app | awk '{print $1}')
## Wait for 3 min for Pod to start up.
retry=6
echo "Waiting for 3 mins for the pod to run."
while [ $retry -gt 0 ]
do
    retry=`expr $retry - 1`
    str1=$( oc get pods -n mas-devops | grep -i mas-devops-app | grep -i 'running')
    if [[ -n ${str1} ]]; 
    then
      echo "Pod is running"
      break
    fi
    sleep 30;
    echo "Pod is not running, will check again in 30 sec."
done
if [ $retry -eq 0 ]
then
  echo " Pod failed to run correctly in 3 Mins!!! "
  echo " Please check what's wrong and re-run the install script."
  exit 1
fi

## Cleanup in case of a second run
oc exec $POD -- rm -rf /opt/app-root/src/masloc
## Clone the latest collection
oc exec $POD -- git clone https://github.com/ibm-mas/ansible-devops /opt/app-root/src/masloc/ansible-devops
## Creates the directory where all the MAS configuration will go
oc exec $POD -- mkdir /opt/app-root/src/masloc/masconfig
# Upload the playbook to install MAS on OCP
oc cp masocpl.yml $POD:/opt/app-root/src/masloc/ansible-devops/ibm/mas_devops/playbooks
## Uploads your MAS license file and UDS certificate
oc cp license.dat mas-devops/$POD:/opt/app-root/src/masloc
IFS=' '
read -a strarr <<< $(oc exec $POD -- bash -c "cd masloc/ansible-devops/ibm/mas_devops && ansible-galaxy collection build --force" | grep -i 'Created collection')
oc exec $POD -- bash -c "cd masloc/ansible-devops/ibm/mas_devops && ansible-galaxy collection install ${strarr[5]} --force"
## Run the playbook
oc exec $POD -- bash -c "cd masloc/ansible-devops/ibm/mas_devops && export MAS_APP_SETTINGS_DEMODATA=True && ansible-playbook ibm.mas_devops.masocpl"
