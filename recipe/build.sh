#!/bin/bash

set -ex

# https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export IS_IN_RERUN_WORKSPACE=no

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml 

# The CI environment variable means something specific to Rerun. Unset it.
unset CI

case "$target_platform" in
    "linux-64")
        export RUST_TARGET="x86_64-unknown-linux-gnu"
        ;;
    "linux-aarch64")
        export RUST_TARGET="aarch64-unknown-linux-gnu"
        ;;
    "osx-64")
        export RUST_TARGET="x86_64-apple-darwin"
        ;;
    "osx-arm64")
        export RUST_TARGET="aarch64-apple-darwin"
        ;;
    "win-64")
        export RUST_TARGET="x86_64-pc-windows-msvc"
        ;;
esac

if [[ $CONDA_BUILD_CROSS_COMPILATION == "1"  && $target_platform == "osx-arm64" ]]; then
    export CROSS_TARGET="--target aarch64-apple-darwin"
else
    export CROSS_TARGET=""
fi

# Build the rerun-cli and insert it into the python package
cargo build --package rerun-cli $CROSS_TARGET --no-default-features --features native_viewer,nasm --release
cp target/$RUST_TARGET/release/rerun rerun_py/rerun_sdk/rerun_cli/rerun 

# Build the rerun-web-viewer assets
cargo run --locked -p re_dev_tools -- build-web-viewer --release -g

# Run the maturin build via pip which works for direct and
# cross-compiled builds.
MATURIN_PEP517_ARGS="$CROSS_TARGET --features pypi" "${PYTHON}" -m pip install rerun_py/ -vv

npm i yarn
npx yarn install --cwd rerun_js
npx yarn --cwd rerun_js/web-viewer run build
"${PYTHON}" -m pip install rerun_notebook/ -vv
