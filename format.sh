#!/bin/bash

set -o errexit -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
(cd $script_dir && clang-format -i *.mm *.h)
