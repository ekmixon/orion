#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e
set -x

cd "$HOME"

su worker -c /home/worker/launch-grizzly-worker.sh

# need to keep the container running
while true
do
    if [ "$EC2SPOTMANAGER_PROVIDER" = "EC2Spot" ]
    then
        /usr/local/bin/screenlog-to-cloudwatch.py || true
    fi
    sleep 60
done
