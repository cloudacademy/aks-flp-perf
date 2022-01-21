#!/bin/bash

# script name: aks-flp-perf.sh
# Version v0.0.1 20220121
# Set of tools to deploy AKS troubleshooting labs

# "-l|--lab" Lab scenario to deploy
# "-r|--region" region to deploy the resources
# "-u|--user" User alias to add on the lab name
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=`getopt -o g:n:l:r:u:hv --long resource-group:,name:,lab:,region:,user:,help,validate,version -n 'aks-flp-perf.sh' -- "$@"`
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
USER_ALIAS=""
LOCATION="uksouth"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;
        -u|--user) case "$2" in
            "") shift 2;;
            *) USER_ALIAS="$2"; shift 2;;
            esac;;    
        -v|--validate) VALIDATE=1; shift;;
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.0.1 20220121"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\n--> Warning: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login -o table
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    RG_EXIST=$(az group show -g $RESOURCE_GROUP &>/dev/null; echo $?)
    if [ $RG_EXIST -ne 0 ]
    then
        echo -e "\n--> Creating resource group ${RESOURCE_GROUP}...\n"
        az group create --name $RESOURCE_GROUP --location $LOCATION -o table &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\n--> Cluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 5
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -ne 0 ]
    then
        echo -e "\n--> ERROR: Failed to create cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP ...\n"
        exit 5
    fi
}

# Usage text
function print_usage_text () {
    NAME_EXEC="aks-flp-perf"
    echo -e "$NAME_EXEC usage: $NAME_EXEC -l <LAB#> -u <USER_ALIAS> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
*************************************************************************************
*\t 1. Pod in CrashLoopBackOff
*\t 2. 2. Memory usage top offender
*\t 3. 
*************************************************************************************\n"
}

# Lab scenario 1
function lab_scenario_1 () {
    CLUSTER_NAME=aks-perf-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-perf-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --tag aks-perf-lab=${LAB_SCENARIO} \
    --generate-ssh-keys \
    --yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

kubectl create ns workload &>/dev/null
cat <<EOF | kubectl -n workload apply -f &>/dev/null -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: importantapp
  labels:
    app: importantapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: importantapp
  template:
    metadata:
      labels:
        app: importantapp
    spec:
        containers:
        - name: importantpod
          image: polinux/stress
          resources:
            requests:
              memory: "50Mi"
            limits:
              memory: "200Mi"
          command: ["stress"]
          args: ["--vm", "1", "--vm-bytes", "300M", "--vm-hang", "1"]
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    sleep 30
    echo -e "\n\n************************************************************************\n"
    echo -e "\n--> Issue description: \n The deployment \"importantapp\" in the workload namespace has a pod in CrashLoopBackoff \n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_1_validation () {
    CLUSTER_NAME=aks-perf-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-perf-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags -o yaml 2>/dev/null | grep aks-perf-lab | cut -d ' ' -f2 | tr -d "'")"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        RUNNING_POD="$(kubectl -n workload get po -l app=importantapp | grep Running | wc -l 2>/dev/null)"
        if [ $RUNNING_POD -ge 1 ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nThe importantapp pod in $CLUSTER_NAME looks good now\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 2
function lab_scenario_2 () {
    CLUSTER_NAME=aks-perf-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-perf-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --tag aks-perf-lab=${LAB_SCENARIO} \
    --generate-ssh-keys \
    --yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

kubectl create ns workload &>/dev/null
cat <<EOF | kubectl -n workload apply -f &>/dev/null -
---
apiVersion: v1
kind: Service
metadata:
  name: productcatalogue
  labels:
    app: productcatalogue
spec:
  type: NodePort
  selector:
    app: productcatalogue
  ports:
  - protocol: TCP
    port: 8020
    name: http
---
apiVersion: v1
kind: ReplicationController
metadata:
  name: productcatalogue
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: productcatalogue
    spec:
      containers:
      - name: productcatalogue
        image: danielbryantuk/djproductcatalogue:1.0
        ports:
        - containerPort: 8020
        livenessProbe:
          httpGet:
            path: /healthcheck
            port: 8025
          initialDelaySeconds: 30
          timeoutSeconds: 1
---
apiVersion: v1
kind: Service
metadata:
  name: shopfront
  labels:
    app: shopfront
spec:
  type: NodePort
  selector:
    app: shopfront
  ports:
  - protocol: TCP
    port: 8010
    name: http

---
apiVersion: v1
kind: ReplicationController
metadata:
  name: shopfront
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: shopfront
    spec:
      containers:
      - name: djshopfront
        image: danielbryantuk/djshopfront:1.0
        ports:
        - containerPort: 8010
        livenessProbe:
          httpGet:
            path: /health
            port: 8010
          initialDelaySeconds: 30
          timeoutSeconds: 1
---
apiVersion: v1
kind: Service
metadata:
  name: stockmanager
  labels:
    app: stockmanager
spec:
  type: NodePort
  selector:
    app: stockmanager
  ports:
  - protocol: TCP
    port: 8030
    name: http

---
apiVersion: v1
kind: ReplicationController
metadata:
  name: stockmanager
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: stockmanager
    spec:
      containers:
      - name: stockmanager
        image: danielbryantuk/djstockmanager:1.0
        ports:
        - containerPort: 8030
        livenessProbe:
          httpGet:
            path: /health
            port: 8030
          initialDelaySeconds: 30
          timeoutSeconds: 1
EOF

cat <<EOF | kubectl apply -f &>/dev/null -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    component: custom-check
  name: custom-check
  namespace: kube-system
spec:
  selector:
    matchLabels:
      component: custom-check
      tier: node
  template:
    metadata:
      labels:
        component: custom-check
        tier: node
    spec:
      containers:
      - name: custom-check
        image: alpine
        imagePullPolicy: IfNotPresent
        command:
          - nsenter
          - --target
          - "1"
          - --mount
          - --uts
          - --ipc
          - --net
          - --pid
          - --
          - sh
          - -c
          - |
            while true; do ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -2 | grep -v 'PPID' | awk '{print \$1}'; sleep 30; done
        resources:
          requests:
            cpu: 50m
        securityContext:
          privileged: true
      dnsPolicy: ClusterFirst
      hostPID: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
      restartPolicy: Always
  updateStrategy:
    type: OnDelete
EOF
    
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    while true; do for s in / - \\ \|; do printf "\r$s"; sleep 1; done; done &
    sleep 30
    kill $!; trap 'kill $!' SIGTERM
    echo -e "\n\n********************************************************"
    echo -e "\n--> Issue description: \nIdentify what is the process ID that is consuming more memory in the worker node\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_2_validation () {
    CLUSTER_NAME=aks-perf-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-perf-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags -o yaml 2>/dev/null | grep aks-perf-lab | cut -d ' ' -f2 | tr -d "'")"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        TOP_PID="$(kubectl logs --tail=1 -l component=custom-check -n kube-system 2>/dev/null)"
        echo -e "Enter the process ID which is using most of the memory from the node\n"
        read -p 'PID: ' USER_PID
        RE='^[0-9]+$'
        if ! [[ $USER_PID =~ $RE ]]
        then
            echo -e "ERROR: The PID value $USER_PID is not valid...\n"
            exit 12
        fi
        if [ "$TOP_PID" == "$USER_PID" ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nYour answer is correct, the top offender process ID is $USER_PID\n"
        else
            echo -e "\nIncorrect answer provided, try again...\n"
        fi
    else
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 3
function lab_scenario_3 () {
    CLUSTER_NAME=aks-perf-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-perf-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME
    
    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --api-server-authorized-ip-ranges 0.0.0.0/32 \
    --generate-ssh-keys \
    --tag aks-perf-lab=${LAB_SCENARIO} \
	--yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\n********************************************************"
    echo -e "\n--> Issue description: \nCluster API not reachable, kubectl commands failing\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_3_validation () {
CLUSTER_NAME=aks-perf-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-perf-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags -o yaml 2>/dev/null | grep aks-perf-lab | cut -d ' ' -f2 | tr -d "'")"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        while true; do for s in / - \\ \|; do printf "\r$s"; sleep 1; done; done &
        API_CONNECTION_STATUS="$(timeout 15 kubectl get no &>/dev/null; echo $?)"
        kill $!; trap 'kill $!' SIGTERM
        if [ $API_CONNECTION_STATUS -eq 0 ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nThe $CLUSTER_NAME cluster API is now reachable\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	print_usage_text
    echo -e '"-l|--lab" Lab scenario to deploy (3 possible options)
"-r|--region" region to create the resources
"--version" print version of aks-flp-perf
"-h|--help" help info\n'
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z $LAB_SCENARIO ]; then
	echo -e "\n--> Error: Lab scenario value must be provided. \n"
	print_usage_text
	exit 9
fi

if [ -z $USER_ALIAS ]; then
	echo -e "Error: User alias value must be provided. \n"
	print_usage_text
	exit 10
fi

# lab scenario has a valid option
if [[ ! $LAB_SCENARIO =~ ^[1-2]+$ ]];
then
    echo -e "\n--> Error: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 3\n"
    exit 11
fi

# main
echo -e "\n--> AKS Troubleshooting sessions
********************************************

This tool will use your default subscription to deploy the lab environments.
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_1

elif [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_1_validation

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_2

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_2_validation

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_3

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_3_validation
else
    echo -e "\n--> Error: no valid option provided\n"
    exit 12
fi

exit 0