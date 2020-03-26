#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e
set -x
set -o pipefail

# shellcheck source=recipes/linux/common.sh
source "${0%/*}/common.sh"

#### Install Berglas

apt-install-auto ca-certificates curl

# A tool for managing secrets on Google Cloud.
# https://github.com/GoogleCloudPlatform/berglas

AMD64_DOWNLOAD_URL="https://storage.googleapis.com/berglas/master/linux_amd64/berglas"

if is-amd64; then
  curl -sL --retry 5 "$AMD64_DOWNLOAD_URL" -o /usr/local/bin/berglas
  chmod +x /usr/local/bin/berglas
fi