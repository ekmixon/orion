#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e
set -x
set -o pipefail

# shellcheck source=recipes/linux/common.sh
source /home/ubuntu/.local/bin/common.sh

if [[ "$(id -u)" = "0" ]]
then
  function tc-get-secret () {
    TASKCLUSTER_ROOT_URL="${TASKCLUSTER_PROXY_URL-$TASKCLUSTER_ROOT_URL}" retry taskcluster api secrets get "project/fuzzing/$1"
  }

  # Config and run the logging service
  mkdir -p /etc/google/auth /var/lib/td-agent-bit/pos
  tc-get-secret google-logging-creds | jshon -e secret -e key > /etc/google/auth/application_default_credentials.json
  chmod 0600 /etc/google/auth/application_default_credentials.json
  /opt/td-agent-bit/bin/td-agent-bit -c /etc/td-agent-bit/td-agent-bit.conf

  function onexit () {
    echo "Saving ~/work to /logs/work.tar.zst" >&2
    #tar -C /home/ubuntu -c work | zstd -f -o /logs/work.tar.zst
    #tar -c /home/ubuntu | zstd -f -o /logs/work.tar.zst
    echo "Waiting for logs to flush..." >&2
    sleep 15
    killall -INT td-agent-bit
    sleep 15
    #cp /home/ubuntu/* /logs/
  }
  trap onexit EXIT

  # set sysctls defined in setup.sh
  sysctl --load /etc/sysctl.d/60-fuzzilli.conf

  su ubuntu -c "$0"
else
  echo "Launching fuzzilli run."
  ./fuzzilli.sh
fi
