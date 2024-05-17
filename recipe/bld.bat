@echo on
REM https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
set CARGO_NET_GIT_FETCH_WITH_CLI=true

REM Point PyO3 to the right interpreter
set "PYO3_PYTHON=%PYTHON%"

REM The CI environment variable means something specific to Rerun. Unset it.
set CI=
set IS_IN_RERUN_WORKSPACE=no

REM Bundle all downstream library licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
if errorlevel 1 exit 1

REM Run the maturin build via pip
set PYTHONUTF8=1
set PYTHONIOENCODING="UTF-8"

REM Build the rerun-cli and insert it into the python package
cargo build --package rerun-cli --no-default-features --features native_viewer --release
cp target/release/rerun-cli rerun_py/rerun_sdk/rerun_cli/rerun

REM Build the rerun-web-viewer assets
cargo run --locked -p re_dev_tools -- build-web-viewer --release -g

set MATURIN_PEP517_ARGS=--features pypi
%PYTHON% -m pip install rerun_py/ -vv
