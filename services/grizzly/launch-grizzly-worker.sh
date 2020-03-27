#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e
set -x
set -o pipefail

wait_token="$1"
shift

# shellcheck source=recipes/linux/common.sh
source ~/.local/bin/common.sh

function update_ec2_status {
  if [[ -n "$EC2SPOTMANAGER_POOLID" ]]; then
    python3 -m EC2Reporter --report "$@" || true
  fi
}

eval "$(ssh-agent -s)"
mkdir -p .ssh

# Get AWS credentials for GCE to be able to read from Credstash
if [ "$EC2SPOTMANAGER_PROVIDER" = "GCE" ]; then
  mkdir -p .aws
  retry berglas access fuzzmanager-cluster-secrets/credstash-aws-auth > .aws/credentials
  chmod 0600 .aws/credentials
elif [ -n "$TASK_ID" ] && [ -n "$TASKCLUSTER_PROXY_URL" ]; then
  mkdir -p .aws
  curl -L "$TASKCLUSTER_PROXY_URL/secrets/v1/secret/project/fuzzing/credstash-aws-auth" | jshon -e secret -e key -u > .aws/credentials
  chmod 0600 .aws/credentials
fi

# install authorized keys
retry credstash get grizzly-ssh-authorized-keys >> .ssh/authorized_keys

# Get fuzzmanager configuration from credstash
retry credstash get fuzzmanagerconf > .fuzzmanagerconf

# Update fuzzmanager config for this instance
mkdir -p signatures
cat >> .fuzzmanagerconf << EOF
sigdir = $HOME/signatures
tool = bearspray
EOF
case "$EC2SPOTMANAGER_PROVIDER" in
  EC2Spot)
    SHIP=EC2
    ;;
  GCE)
    SHIP=GCE
    ;;
  *)
    if [ -n "$TASKCLUSTER_ROOT_URL" ] && [ -n "$TASK_ID" ]; then
      SHIP=Taskcluster
    fi
    ;;
esac
setup-fuzzmanager-hostname "$SHIP"
chmod 0600 .fuzzmanagerconf

# only clone if it wasn't already mounted via docker run -v
if [ ! -d ~/bearspray ]; then
  update_ec2_status "Setup: cloning bearspray"

  # Get deployment key from credstash
  retry credstash get deploy-bearspray.pem > .ssh/id_ecdsa.bearspray
  chmod 0600 .ssh/id_ecdsa.bearspray

  cat <<- EOF >> .ssh/config

	Host bearspray
	HostName github.com
	IdentitiesOnly yes
	IdentityFile ~/.ssh/id_ecdsa.bearspray
	EOF

  # Checkout bearspray
  git init bearspray
  ( cd bearspray
    git remote add -t master origin git@bearspray:MozillaSecurity/bearspray.git
    retry git fetch -v --depth 1 --no-tags origin master
    git reset --hard FETCH_HEAD
  )
fi

update_ec2_status "Setup: installing bearspray"
pip3 install --user -U -e ./bearspray

update_ec2_status "Setup: launching bearspray"

screen -dmLS grizzly /bin/bash
sleep 5
screen -S grizzly -X screen rwait run "$wait_token" python3 -m bearspray --screen --xvfb
