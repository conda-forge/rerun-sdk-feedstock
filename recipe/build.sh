#!/bin/bash

set -ex

# https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export IS_IN_RERUN_WORKSPACE=no

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml 

# The CI environment variable means something specific to Rerun. Unset it.
unset CI

# TODO(nick): Parse Major version from clang instead of hardocoding it.
CLANG_MAJOR_VERSION="16"
CLANG_RESOURCE_DIR="${CONDA_PREFIX}/lib/clang/$CLANG_MAJOR_VERSION"
# Use libclang's include directory which has the standard headers
LIBCLANG_INCLUDE="${CONDA_PREFIX}/lib/clang/$CLANG_MAJOR_VERSION/include"

case "$target_platform" in
    "linux-64")
        export CFLAGS_wasm32_unknown_unknown="-isystem $LIBCLANG_INCLUDE -resource-dir $CLANG_RESOURCE_DIR"
        export CC_wasm32_unknown_unknown="${CONDA_PREFIX}/bin/clang"
        export RUST_TARGET="x86_64-unknown-linux-gnu"
        ;;
    "linux-aarch64")
        export CFLAGS_wasm32_unknown_unknown="-isystem $LIBCLANG_INCLUDE -resource-dir $CLANG_RESOURCE_DIR"
        export CC_wasm32_unknown_unknown="${CONDA_PREFIX}/bin/clang"
        export RUST_TARGET="aarch64-unknown-linux-gnu"
        ;;
    "osx-64")
        CLANG_MAJOR_VERSION="19"
        CLANG_RESOURCE_DIR="${CONDA_PREFIX}/lib/clang/$CLANG_MAJOR_VERSION"
        # Use libclang's include directory which has the standard headers
        LIBCLANG_INCLUDE="${CONDA_PREFIX}/lib/clang/$CLANG_MAJOR_VERSION/include"

        export AR="${CONDA_PREFIX}/bin/llvm-ar"
        export CFLAGS_wasm32_unknown_unknown="-isystem $LIBCLANG_INCLUDE -resource-dir $CLANG_RESOURCE_DIR"
        # Hmm it should use the target specific flags but it doesn't
        export TARGET_CFLAGS="-isystem $LIBCLANG_INCLUDE -resource-dir $CLANG_RESOURCE_DIR"
        # This might impact performance, and break something else but is needed for ring wasm target
        export CFLAGS="-isystem $LIBCLANG_INCLUDE -resource-dir $CLANG_RESOURCE_DIR"
        export CC_wasm32_unknown_unknown="${CONDA_PREFIX}/bin/clang"
        # Since we clobber CFLAGS need to clobber CC as well
        export CC="${CONDA_PREFIX}/bin/clang"
        export CC_x86_64_apple_darwin="${CONDA_PREFIX}/bin/clang"
        export RUST_TARGET="x86_64-apple-darwin"
        ;;
    "osx-arm64")
        export AR="${CONDA_PREFIX}/bin/llvm-ar"
        export RUST_TARGET="aarch64-apple-darwin"
        ;;
    "win-64")
        export AR="${CONDA_PREFIX}/bin/llvm-ar"
        export RUST_TARGET="x86_64-pc-windows-msvc"
        ;;
esac

# Need to disable stack-protector for wasm-bindgen
export CFLAGS_wasm32_unknown_unknown="${CFLAGS_wasm32_unknown_unknown} -fno-stack-protector"
export CXXFLAGS_wasm32_unknown_unknown="${CXXFLAGS_wasm32_unknown_unknown} -fno-stack-protector"

if [[ $CONDA_BUILD_CROSS_COMPILATION == "1"  && $target_platform == "osx-arm64" ]]; then
    export CROSS_TARGET="--target aarch64-apple-darwin"
else
    export CROSS_TARGET=""
fi

"${PYTHON}" -m pip install rerun_pixi_env/
ensure-pyo3-build-cfg

# Build the rerun-web-viewer assets
cargo run --locked -p re_dev_tools -- build-web-viewer --no-default-features --features analytics,map_view --release -g

# Build the rerun-cli and insert it into the python package
cargo build --package rerun-cli $CROSS_TARGET --no-default-features --features release_full --release
cp target/$RUST_TARGET/release/rerun rerun_py/rerun_sdk/rerun_cli/rerun 

# Run the maturin build via pip which works for direct and
# cross-compiled builds.
MATURIN_PEP517_ARGS="$CROSS_TARGET --features pypi" "${PYTHON}" -m pip install rerun_py/ -vv

npm i yarn
npx yarn install --cwd rerun_js
npx yarn --cwd rerun_js/web-viewer run build
"${PYTHON}" -m pip install rerun_notebook/ -vv
