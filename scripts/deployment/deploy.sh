#!/bin/bash

set -o xtrace

# See https://github.com/internetarchive/openlibrary/wiki/Deployment-Scratchpad
SERVERS="ol-home0 ol-covers0 ol-web1 ol-web2"
COMPOSE_FILE="docker-compose.yml:docker-compose.production.yml"
REPO_DIRS="/opt/olsystem /opt/openlibrary"

# This script must be run on ol-home0 to start a new deployment.
HOSTNAME="${HOSTNAME:-$HOST}"
if [[ $HOSTNAME != ol-home0.* ]]; then
    echo "FATAL: Must only be run on ol-home0" ;
    exit 1 ;
fi

# Ensure GNU parallel is installed
if [[ $(parallel --version) = GNU* ]]; then
  echo 'installed'
else
  sudo apt-get -y --no-install-recommends install parallel
fi

echo "Starting production deployment at $(date)"

# `sudo git pull origin master` the core Open Library repos:
parallel -v ssh {1} "cd {2} && git pull origin master" ::: $SERVERS ::: $REPO_DIRS

# booklending utils requires login
for SERVER in $SERVERS; do
  ssh $SERVER '[ -d /opt/booklending_utils ] && cd /opt/booklending_utils && git pull origin master'
done

# Prune old images now ; this should remove any unused images
parallel -v ssh {} "docker image prune -f" ::: $SERVERS

# Pull the latest docker images
parallel -v ssh {} "cd /opt/openlibrary && COMPOSE_FILE=\"$COMPOSE_FILE\" docker-compose --profile {} pull" ::: $SERVERS

# Add a git SHA tag to the Docker image to facilitate rapid rollback
cd /opt/openlibrary
CUR_SHA=$(git rev-parse HEAD | head -c7)
parallel -v ssh {} "echo 'FROM openlibrary/olbase:latest' | docker build -t 'openlibrary/olbase:$CUR_SHA' -" ::: $SERVERS

# And tag the deploy!
DEPLOY_TAG="deploy-$(date +%Y-%m-%d)"
sudo git tag $DEPLOY_TAG
sudo git push origin $DEPLOY_TAG

echo "Finished production deployment at $(date)"
echo "To reboot the servers, please run scripts/deployments/restart_all_servers.sh"
