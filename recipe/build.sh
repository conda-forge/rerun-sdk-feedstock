#!/bin/bash

set -ex

# https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
export CARGO_NET_GIT_FETCH_WITH_CLI=true

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml 

# Run the maturin build via pip which works for direct and
# cross-compiled builds.
"${PYTHON}" -m pip install rerun_py/ -vv