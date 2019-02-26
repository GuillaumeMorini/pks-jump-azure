#!/usr/bin/env bash
source .env.sh
MYSELF=$(basename $0)
mkdir -p ${LOG_DIR}/
exec &> >(tee -a "${LOG_DIR}/${MYSELF}.$(date '+%Y-%m-%d-%H').log")
exec 2>&1
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -n|--NO_DOWNLOAD)
    NO_DOWNLOAD=TRUE
    shift # past argument
    #shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters
source ~/.env.sh


PCF_OPSMAN_ADMIN_PASSWD=${PIVNET_UAA_TOKEN}
PKS_KEY_PEM=$(cat ${HOME_DIR}/${PKS_SUBDOMAIN_NAME}.${PKS_DOMAIN_NAME}.key | awk '{printf "%s\\r\\n", $0}')
PKS_CERT_PEM=$(cat ${HOME_DIR}/fullchain.cer | awk '{printf "%s\\r\\n", $0}')
PKS_CREDHUB_KEY="01234567890123456789"
PKS_API_HOSTNAME="api.${PKS_SUBDOMAIN_NAME}.${PKS_DOMAIN_NAME}"
PKS_LB="${ENV_NAME}-pks-lb"
cd ${HOME_DIR}

PIVNET_ACCESS_TOKEN=$(curl \
  --fail \
  --header "Content-Type: application/json" \
  --data "{\"refresh_token\": \"${PIVNET_UAA_TOKEN}\"}" \
  https://network.pivotal.io/api/v2/authentication/access_tokens |\
    jq -r '.access_token')

### accept 170er stemcells
RELEASE_JSON=$(curl \
  --header "Authorization: Bearer ${PIVNET_ACCESS_TOKEN}" \
  --fail \
  "https://network.pivotal.io/api/v2/products/233/releases/286469")
# eula acceptance link
EULA_ACCEPTANCE_URL=$(echo ${RELEASE_JSON} |\
  jq -r '._links.eula_acceptance.href')

# eula acceptance
curl \
  --fail \
  --header "Authorization: Bearer ${PIVNET_ACCESS_TOKEN}" \
  --request POST \
  ${EULA_ACCEPTANCE_URL}


echo $(date) start downloading helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh
echo $(date) end downloading helm




cat << EOF > ${TEMPLATE_DIR}/pks_vars.yaml
subscription_id: ${AZURE_SUBSCRIPTION_ID}
tenant_id: ${AZURE_TENANT_ID}
resource_group_name: ${ENV_NAME}
azure_location: ${LOCATION}
pks_web_lb: ${PKS_WEB_LB}
vnet_name: ${ENV_NAME}-virtual-network
default_security_group: ${ENV_NAME}-pks-api-sg
pks_cert_pem: "${PKS_CERT_PEM}"
pks_key_pem: "${PKS_KEY_PEM}"
pks_api_hostname: "${PKS_API_HOSTNAME}"
pks_lb: "${PKS_LB}"
primary_availability_set: "${ENV_NAME}-availability-set"
pks_master_identity: "pks-master"
pks_worker_identity: "pks-worker"
EOF

if  [ -z ${NO_APPLY} ] ; then
  echo "Now deploying PKS Tile"
  ${SCRIPT_DIR}/deploy_tile.sh -t pks -s -d
  echo "Now calling Harbor deployment"
  ${SCRIPT_DIR}/deploy_harbor.sh -lb -a
  echo "Now creating pks admin user"
  ${SCRIPT_DIR}/create_user.sh
  echo "now creating k8s loadbalancer k8s1"
  ${SCRIPT_DIR}/create_lb.sh --K8S_CLUSTER_NAME k8s1
  echo "now creating k8s cluster k8s1"
  ${SCRIPT_DIR}/create_cluster.sh --K8S_CLUSTER_NAME k8s1
else
  echo "No Product Apply"
fi
echo "$(date) end deploy PKS"
