#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e
set -x

# Build radamsa
cd /tmp
git clone -v --depth 1 https://gitlab.com/akihe/radamsa.git
( cd radamsa
  make
  make install
)
rm -rf radamsa
