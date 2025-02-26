#!/bin/bash

set -o xtrace

# See https://github.com/internetarchive/openlibrary/wiki/Deployment-Scratchpad
SERVERS="ol-home0 ol-covers0 ol-web1 ol-web2"
COMPOSE_FILE="docker-compose.yml:docker-compose.production.yml"

# This script must be run on ol-home0 to start a new deployment.
HOSTNAME="${HOSTNAME:-$HOST}"
if [[ $HOSTNAME != ol-home0.* ]]; then
    echo "FATAL: Must only be run on ol-home0" ;
    exit 1 ;
fi

# Install GNU parallel if not there
# Check is GNU-specific because some hosts had something else called parallel installed
[[ $(parallel --version 2>/dev/null) = GNU* ]] || sudo apt-get -y --no-install-recommends install parallel

echo "Starting production deployment at $(date)"

# `sudo git pull origin master` the core Open Library repos:
parallel --quote -v ssh {1} "cd {2} && sudo git pull origin master" ::: $SERVERS ::: /opt/olsystem /opt/openlibrary

# booklending utils requires login
for SERVER in $SERVERS; do
  ssh $SERVER 'if [ -d /opt/booklending_utils ]; then cd /opt/booklending_utils && sudo git pull origin master; fi'
done

# Prune old images now ; this should remove any unused images
parallel --quote -v ssh {} "docker image prune -f" ::: $SERVERS

# Pull the latest docker images
parallel --quote -v ssh {} "cd /opt/openlibrary && COMPOSE_FILE=\"$COMPOSE_FILE\" docker-compose --profile {} pull" ::: $SERVERS

# Add a git SHA tag to the Docker image to facilitate rapid rollback
cd /opt/openlibrary
CUR_SHA=$(git rev-parse HEAD | head -c7)
parallel --quote -v ssh {} "echo 'FROM openlibrary/olbase:latest' | docker build -t 'openlibrary/olbase:$CUR_SHA' -" ::: $SERVERS

# And tag the deploy!
DEPLOY_TAG="deploy-$(date +%Y-%m-%d)"
sudo git tag $DEPLOY_TAG
sudo git push origin $DEPLOY_TAG

echo "Finished production deployment at $(date)"
echo "To reboot the servers, please run scripts/deployments/restart_all_servers.sh"
