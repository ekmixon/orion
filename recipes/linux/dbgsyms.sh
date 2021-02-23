#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e
set -x
set -o pipefail

# shellcheck source=recipes/linux/common.sh
source "${0%/*}/common.sh"

#### Setup the Ubuntu debug symbol server (https://wiki.ubuntu.com/DebuggingProgramCrash)

apt-install-auto \
  ca-certificates \
  curl \
  software-properties-common \
  gpg \
  gpg-agent

if [ ! -f /etc/apt/sources.list.d/ddebs.list ]; then
  cat <<- EOF > /etc/apt/sources.list.d/ddebs.list
	deb http://ddebs.ubuntu.com/ $(lsb_release -cs) main restricted universe multiverse
	deb http://ddebs.ubuntu.com/ $(lsb_release -cs)-updates main restricted universe multiverse
	deb http://ddebs.ubuntu.com/ $(lsb_release -cs)-proposed main restricted universe multiverse
	EOF

  curl --retry 5 -sL http://ddebs.ubuntu.com/dbgsym-release-key.asc | apt-key add -
  sys-update
fi

# For each package, install the corresponding dbgsym package (same version).
function sys-embed-dbgsym () {
  dbgsym_installs=()
  for pkg in "$@"; do
    if ver="$(dpkg-query -W "$pkg" 2>/dev/null | cut -f2)"; then
      dbgsym_installs+=("$pkg-dbgsym=$ver")
    else
      echo "WARNING: $pkg not installed, but we checked for dbgsyms?" 1>&2
    fi
  done
  if [ ${#dbgsym_installs[@]} -ne 0 ]; then
    sys-embed "${dbgsym_installs[@]}"
  fi
}
