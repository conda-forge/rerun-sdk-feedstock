@echo on
REM https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
set CARGO_NET_GIT_FETCH_WITH_CLI=true

REM Point PyO3 to the right interpreter
set "PYO3_PYTHON=%PYTHON%"

REM The CI environment variable means something specific to Rerun. Unset it.
set CI=
set IS_IN_RERUN_WORKSPACE=no

REM conda's compiler activation configures the native compiler and archiver.
REM Rust's cc crate gives target-qualified tool variables precedence, so keep the
REM LLVM toolchain scoped to the web viewer's WASM target. Clang compiles native
REM sources for wasm32, and llvm-ar avoids host-specific archives.
set "CC_wasm32_unknown_unknown=clang"
set "CXX_wasm32_unknown_unknown=clang++"
set "AR_wasm32_unknown_unknown=llvm-ar"

REM Configure Rust to use conda-installed wasm32 target
REM Try multiple possible locations where conda might install the target
set WASM_TARGET_FOUND=0
if exist "%CONDA_PREFIX%\Library\lib\rustlib\wasm32-unknown-unknown" (
    echo Found wasm32 target in Library\lib\rustlib
    set "RUST_TARGET_PATH=%CONDA_PREFIX%\Library\lib\rustlib"
    set WASM_TARGET_FOUND=1
) else if exist "%CONDA_PREFIX%\lib\rustlib\wasm32-unknown-unknown" (
    echo Found wasm32 target in lib\rustlib
    set "RUST_TARGET_PATH=%CONDA_PREFIX%\lib\rustlib"
    set WASM_TARGET_FOUND=1
) else (
    echo Searching for wasm32 target in conda environment...
    dir "%CONDA_PREFIX%" /s /b | findstr "wasm32-unknown-unknown" 2>nul
    echo Warning: wasm32-unknown-unknown target not found in expected conda locations
)

REM Bundle all downstream library licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
if errorlevel 1 exit 1

REM Run the maturin build via pip
set PYTHONUTF8=1
set PYTHONIOENCODING="UTF-8"

set PIXI_PROJECT_ROOT=%CD%
%PYTHON% -m pip install rerun_pixi_env/
ensure-pyo3-build-cfg

REM Build the rerun-web-viewer assets
set RUST_BACKTRACE=1
REM cc-rs appends target-specific flags to generic flags, so clear conda's
REM native flags only for this WASM build. setlocal restores them before the
REM native CLI and Python extension are built.
setlocal
set "CFLAGS="
set "CXXFLAGS="
set "CPPFLAGS="
set "TARGET_CFLAGS="
set "TARGET_CXXFLAGS="
set "TARGET_CPPFLAGS="
cargo run --locked -p re_dev_tools -- build-web-viewer --no-default-features --features analytics,map_view --release -g
if errorlevel 1 (
    endlocal
    exit /b 1
)
endlocal

REM Build the rerun-cli and insert it into the python package
cargo build --package rerun-cli --no-default-features --features release_full --release
if errorlevel 1 exit 1
REM Since rust_win-64 1.95, activation sets CARGO_BUILD_TARGET, which moves
REM cargo output from target\release to target\%CARGO_BUILD_TARGET%\release
if defined CARGO_BUILD_TARGET (
    copy target\%CARGO_BUILD_TARGET%\release\rerun.exe rerun_py\rerun_sdk\rerun_cli\rerun.exe
) else (
    copy target\release\rerun.exe rerun_py\rerun_sdk\rerun_cli\rerun.exe
)
if errorlevel 1 exit 1

REM Clean up cargo build artifacts
cargo clean

set MATURIN_PEP517_ARGS=--features pypi
%PYTHON% -m pip install rerun_py/ -vv

npm i yarn
npx yarn install --cwd rerun_js

REM The JavaScript package build invokes Cargo for WASM a second time, so it
REM must not inherit conda's native C/C++ flags either.
setlocal
set "CFLAGS="
set "CXXFLAGS="
set "CPPFLAGS="
set "TARGET_CFLAGS="
set "TARGET_CXXFLAGS="
set "TARGET_CPPFLAGS="
npx yarn --cwd rerun_js/web-viewer run build
if errorlevel 1 (
    endlocal
    exit /b 1
)
endlocal

REM Remove node_modules to free up space
rd /s /q rerun_js\node_modules

%PYTHON% -m pip install rerun_notebook/ -vv
