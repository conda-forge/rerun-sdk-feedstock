@echo on
REM https://github.com/rust-lang/cargo/issues/10583#issuecomment-1129997984
set CARGO_NET_GIT_FETCH_WITH_CLI=true

REM Point PyO3 to the right interpreter
set "PYO3_PYTHON=%PYTHON%"

REM Bundle all downstream library licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
if errorlevel 1 exit 1

REM Run the maturin build via pip
set PYTHONUTF8=1
set PYTHONIOENCODING="UTF-8"

cargo run --locked -p re_build_web_viewer -- --release

set MATURIN_PEP517_ARGS=--features pypi
%PYTHON% -m pip install rerun_py/ -vv
