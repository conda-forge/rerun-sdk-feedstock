@echo on
REM https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
set CARGO_NET_GIT_FETCH_WITH_CLI=true

REM Point PyO3 to the right interpreter
set "PYO3_PYTHON=%PYTHON%"

REM The CI environment variable means something specific to Rerun. Unset it.
set CI=
set IS_IN_RERUN_WORKSPACE=no
::set "AR=%CONDA_PREFIX%\Library\bin\llvm-ar.exe"
set AR=llvm-ar
set CLANG_MAJOR_VERSION=18
set CLANG_RESOURCE_DIR=%CONDA_PREFIX%\Library\lib\clang\%CLANG_MAJOR_VERSION%
set LIBCLANG_INCLUDE=%CONDA_PREFIX%\Library\lib\clang\%CLANG_MAJOR_VERSION%\include
set CFLAGS_wasm32_unknown_unknown=-isystem %LIBCLANG_INCLUDE% -resource-dir %CLANG_RESOURCE_DIR%
set CC_wasm32_unknown_unknown=clang

REM Bundle all downstream library licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
if errorlevel 1 exit 1

REM Run the maturin build via pip
set PYTHONUTF8=1
set PYTHONIOENCODING="UTF-8"

REM Build the rerun-web-viewer assets
cargo run --locked -p re_dev_tools -- build-web-viewer --release -g

REM Build the rerun-cli and insert it into the python package
cargo build --package rerun-cli --no-default-features --features release --release
dir target
dir target\release
copy target\release\rerun.exe rerun_py\rerun_sdk\rerun_cli\rerun.exe

REM Clean up cargo build artifacts
cargo clean

set MATURIN_PEP517_ARGS=--features pypi
%PYTHON% -m pip install rerun_py/ -vv

npm i yarn
npx yarn install --cwd rerun_js
npx yarn --cwd rerun_js/web-viewer run build

REM Remove node_modules to free up space
rd /s /q rerun_js\node_modules

%PYTHON% -m pip install rerun_notebook/ -vv
