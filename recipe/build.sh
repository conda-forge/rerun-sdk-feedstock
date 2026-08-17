#!/bin/bash

set -ex

# https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export IS_IN_RERUN_WORKSPACE=no

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml 

# The CI environment variable means something specific to Rerun. Unset it.
unset CI

# conda's compiler activation configures the native compiler and archiver.
# Rust's cc crate gives target-qualified tool variables precedence, so keep the
# LLVM toolchain scoped to the web viewer's WASM target. Clang compiles native
# sources for wasm32, and llvm-ar avoids host-specific archives.
export CC_wasm32_unknown_unknown="clang"
export CXX_wasm32_unknown_unknown="clang++"
export AR_wasm32_unknown_unknown="llvm-ar"

case "$target_platform" in
    "linux-64")
        export RUST_TARGET="x86_64-unknown-linux-gnu"
        ;;
    "linux-aarch64")
        export RUST_TARGET="aarch64-unknown-linux-gnu"
        # libudev-sys' build script calls the Rust pkg-config crate, which
        # refuses to run when host != target unless this is set. Needed so
        # gilrs-core (gamepad support, new in 0.34.0) can find libudev when
        # cross-compiling to aarch64.
        export PKG_CONFIG_ALLOW_CROSS=1
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

export PIXI_PROJECT_ROOT=$(pwd)
"${PYTHON}" -m pip install rerun_pixi_env/
ensure-pyo3-build-cfg

# cc-rs appends target-specific flags to generic flags. Clear conda's native
# flags for every WASM build so options such as -march and -isystem are not
# passed to clang --target=wasm32-unknown-unknown. Each subshell restores the
# flags before the native CLI and Python extension are built.
run_wasm_build() {
    (
        unset CFLAGS CXXFLAGS CPPFLAGS
        unset TARGET_CFLAGS TARGET_CXXFLAGS TARGET_CPPFLAGS
        "$@"
    )
}

# Build the rerun-web-viewer assets.
run_wasm_build cargo run --locked -p re_dev_tools -- build-web-viewer --no-default-features --features analytics,map_view --release -g

# Build the rerun-cli and insert it into the python package
cargo build --package rerun-cli $CROSS_TARGET --no-default-features --features release_full --release
cp target/$RUST_TARGET/release/rerun rerun_py/rerun_sdk/rerun_cli/rerun 

# Run the maturin build via pip which works for direct and
# cross-compiled builds.
MATURIN_PEP517_ARGS="$CROSS_TARGET --features pypi" "${PYTHON}" -m pip install rerun_py/ -vv

npm i yarn
npx yarn install --cwd rerun_js
# The JavaScript package build invokes Cargo for WASM a second time.
run_wasm_build npx yarn --cwd rerun_js/web-viewer run build
"${PYTHON}" -m pip install rerun_notebook/ -vv
