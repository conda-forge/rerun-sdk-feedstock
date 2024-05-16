#!/bin/bash

set -ex

# https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export IS_IN_RERUN_WORKSPACE=no

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml 

# The CI environment variable means something specific to Rerun. Unset it.
unset CI

if [[ $CONDA_BUILD_CROSS_COMPILATION == "1"  && $target_platform == "osx-arm64" ]]; then
    MATURIN_CROSS_TARGET="--target aarch64-apple-darwin"
fi

cargo run --package rerun-cli --no-default-features --features native_viewer --release
cargo run --locked -p re_dev_tools -- build-web-viewer --release -g
cp target/release/rerun-cli rerun_py/rerun_sdk/rerun_cli/rerun

# Run the maturin build via pip which works for direct and
# cross-compiled builds.
MATURIN_PEP517_ARGS="$MATURIN_CROSS_TARGET --features pypi" "${PYTHON}" -m pip install rerun_py/ -vv
