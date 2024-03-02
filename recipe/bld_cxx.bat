@echo on

REM The CI environment variable means something specific to Rerun. Unset it.
set CI=
set IS_IN_RERUN_WORKSPACE=no

REM Bundle all downstream library licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
if errorlevel 1 exit 1

mkdir build_cxx
cd build_cxx

cmake %CMAKE_ARGS% ^
    -G "Ninja" ^
    -DBUILD_SHARED_LIBS:BOOL=ON ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DRERUN_ARROW_LINK_SHARED:BOOL=ON ^
    -DRERUN_DOWNLOAD_AND_BUILD_ARROW:BOOL=OFF ^
    -DRERUN_INSTALL_RERUN_C:BOOL=OFF ^
    %SRC_DIR%
if errorlevel 1 exit 1

:: Build.
cmake --build . --config Release
if errorlevel 1 exit 1

:: Install.
cmake --build . --config Release --target install
if errorlevel 1 exit 1

:: Test.
.\rerun_cpp\tests\rerun_sdk_tests
if errorlevel 1 exit 1

