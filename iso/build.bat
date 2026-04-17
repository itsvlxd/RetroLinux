@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "PROFILE_DIR=%SCRIPT_DIR%profile"
set "OUTPUT_DIR=%SCRIPT_DIR%out"
set "WORK_DIR=%SCRIPT_DIR%work"

set "ERROR_COUNT=0"
set "CACHE_VOLUME=retrolinux-pkg-cache"

set "INFO_ICON=[INFO] "
set "SUCCESS_ICON=[SUCCESS] "
set "WARN_ICON=[WARN] "
set "ERROR_ICON=[ERROR] "

echo.
echo ██████╗ ███████╗████████╗██████╗  ██████╗     ██╗███████╗ ██████╗ 
echo ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗    ██║██╔════╝██╔═══██╗
echo ██████╔╝█████╗     ██║   ██████╔╝██║   ██║    ██║███████╗██║   ██║
echo ██╔══██╗██╔══╝     ██║   ██╔══██╗██║   ██║    ██║╚════██║██║   ██║
echo ██║  ██║███████╗   ██║   ██║  ██║╚██████╔╝    ██║███████║╚██████╔╝
echo ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝     ╚═╝╚══════╝ ╚═════╝ 
echo.
echo      RetroLinux ISO Build
echo.

call :rx_log INFO "Checking Docker..."

where docker >nul 2>&1
if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Docker is not installed"
    call :rx_log INFO "Install Docker Desktop from: https://docker.com/desktop"
    exit /b 1
)

docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Docker daemon is not running"
    call :rx_log INFO "Start Docker Desktop and wait for it to initialize"
    exit /b 1
)

call :rx_log SUCCESS "Docker is ready"
echo.

set "SKIP_PROMPT=false"
if "%~1"=="-y" set "SKIP_PROMPT=true"
if "%~1"=="--yes" set "SKIP_PROMPT=true"

call :init_cache
if %ERRORLEVEL% neq 0 (
    set /a ERROR_COUNT+=1
    goto :error_exit
)

call :update_cache
if %ERRORLEVEL% neq 0 (
    set /a ERROR_COUNT+=1
    goto :error_exit
)

call :cleanup_build
if %ERRORLEVEL% neq 0 (
    set /a ERROR_COUNT+=1
    goto :error_exit
)

call :prepare_airootfs
if %ERRORLEVEL% neq 0 (
    set /a ERROR_COUNT+=1
    goto :error_exit
)

call :build_iso
if %ERRORLEVEL% neq 0 (
    set /a ERROR_COUNT+=1
    goto :error_exit
)

call :show_stats
exit /b 0

:rx_log
setlocal
set "level=%~1"
set "message=%~2"

if "%level%"=="INFO" (
    echo %INFO_ICON%!message!
) else if "%level%"=="SUCCESS" (
    echo %SUCCESS_ICON%!message!
) else if "%level%"=="WARN" (
    echo %WARN_ICON%!message!
) else if "%level%"=="ERROR" (
    echo %ERROR_ICON%!message!
) else (
    echo [LOG] !message!
)
endlocal & ver > nul
goto :eof

:check_docker
call :rx_log INFO "Checking Docker installation..."

where docker >nul 2>&1
if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Docker is not installed"
    call :rx_log INFO "Please install Docker Desktop from: https://docker.com/desktop"
    exit /b 1
)

call :rx_log INFO "Docker found, checking if daemon is running..."
docker info >nul 2>&1
if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Docker daemon is not running"
    call :rx_log INFO "Please start Docker Desktop and wait for it to initialize"
    exit /b 1
)

call :rx_log SUCCESS "Docker is ready"
exit /b 0

:init_cache
echo.
call :rx_log INFO "Initializing offline package cache..."

docker volume inspect %CACHE_VOLUME% >nul 2>&1
if %ERRORLEVEL% neq 0 (
    docker volume create %CACHE_VOLUME% >nul 2>&1
)

docker run --rm -v %CACHE_VOLUME%:/cache archlinux/archlinux:latest bash -c "test -f /cache/.cache-initialized" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    call :rx_log INFO "Using existing cache"
    exit /b 0
)

call :rx_log INFO "Downloading packages to cache..."

docker run --rm ^
    -v "%PROFILE_DIR%:/profile:ro" ^
    -v "%CACHE_VOLUME%:/packages-cache" ^
    archlinux/archlinux:latest bash -c " ^
        set -e
        pacman -Sy --noconfirm
        grep -v '^#' /profile/packages.x86_64 | grep -v '^$' > /tmp/packages.txt
        mkdir -p /packages-cache /tmp/offlinedb
        pacman -Syw --noconfirm --cachedir /packages-cache --dbpath /tmp/offlinedb $(cat /tmp/packages.txt)
        repo-add /packages-cache/offline.db.tar.gz /packages-cache/*.pkg.tar.zst
        touch /packages-cache/.cache-initialized
    "

if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Failed to initialize package cache"
    exit /b 1
)

call :rx_log SUCCESS "Cache initialized"
exit /b 0

:update_cache
echo.
call :rx_log INFO "Updating offline package cache..."

docker run --rm ^
    -v "%PROFILE_DIR%:/profile:ro" ^
    -v "%CACHE_VOLUME%:/packages-cache" ^
    archlinux/archlinux:latest bash -c " ^
        set -e
        pacman -Sy --noconfirm
        grep -v '^#' /profile/packages.x86_64 | grep -v '^$' > /tmp/packages.txt
        mkdir -p /tmp/offlinedb
        pacman -Syw --noconfirm --cachedir /packages-cache --dbpath /tmp/offlinedb $(cat /tmp/packages.txt)
        rm -f /packages-cache/offline.db.tar.gz
        repo-add /packages-cache/offline.db.tar.gz /packages-cache/*.pkg.tar.zst
    "

if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Failed to update package cache"
    exit /b 1
)

call :rx_log SUCCESS "Cache updated"
exit /b 0

:cleanup_build
echo.

if exist "%WORK_DIR%" (
    if "%SKIP_PROMPT%"=="true" (
        call :rx_log INFO "Cleaning up existing build directory..."
        rmdir /s /q "%WORK_DIR%" 2>nul
    ) else (
        call :rx_log WARN "Existing build directory found"
        set /p "CONFIRM=Delete existing build and continue? [y/N]: "
        if /i "!CONFIRM!"=="y" (
            call :rx_log INFO "Cleaning up existing build directory..."
            rmdir /s /q "%WORK_DIR%" 2>nul
        ) else (
            call :rx_log INFO "Build cancelled"
            exit /b 0
        )
    )
)

for /f "delims=" %%i in ('dir /b "%OUTPUT_DIR%\*.iso" 2^>nul') do (
    if "%SKIP_PROMPT%"=="true" (
        call :rx_log INFO "Deleting old ISO: %%i"
        del /q "%OUTPUT_DIR%\%%i" 2>nul
    ) else (
        set /p "CONFIRM=Delete %%i and continue? [y/N]: "
        if /i "!CONFIRM!"=="y" (
            call :rx_log INFO "Deleting old ISO: %%i"
            del /q "%OUTPUT_DIR%\%%i" 2>nul
        )
    )
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"

exit /b 0

:prepare_airootfs
echo.
call :rx_log INFO "Preparing airootfs offline packages..."

set "OFFLINE_DIR=%PROFILE_DIR%\airootfs\var\cache\retrolinux\mirror\offline"
if not exist "%OFFLINE_DIR%" mkdir "%OFFLINE_DIR%"

docker run --rm ^
    -v "%CACHE_VOLUME%:/cache:ro" ^
    -v "%OFFLINE_DIR%:/dest:rw" ^
    archlinux/archlinux:latest bash -c " ^
        set -e
        mkdir -p /dest
        if [ -d /cache ] && [ -n \"$(ls -A /cache 2>/dev/null)\" ]; then
            cp -r /cache/* /dest/
        else
            echo 'Warning: Cache is empty'
        fi
    "

if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Failed to copy packages to airootfs"
    exit /b 1
)

copy /y "%PROFILE_DIR%\pacman-offline.conf" "%PROFILE_DIR%\airootfs\etc\pacman.conf" >nul

if %ERRORLEVEL% neq 0 (
    call :rx_log ERROR "Failed to copy pacman config"
    exit /b 1
)

call :rx_log SUCCESS "Airootfs prepared"
exit /b 0

:build_iso
echo.

for /f "delims=" %%i in ('git -C "%SCRIPT_DIR%" describe --always --abbrev=8 2^>nul') do set "VERSION=%%i"
for /f "delims=" %%i in ('git -C "%SCRIPT_DIR%" rev-parse --abbrev-ref HEAD 2^>nul') do set "BRANCH=%%i"

if not defined VERSION set "VERSION=unknown"
if not defined BRANCH set "BRANCH=unknown"

call :rx_log INFO "Building RetroLinux ISO %VERSION% (%BRANCH%)..."
call :rx_log INFO "Starting Docker build (this may take a while)..."
echo.

docker run --rm --privileged ^
    -v "%PROFILE_DIR%:/profile:ro" ^
    -v "%WORK_DIR%:/work" ^
    -v "%OUTPUT_DIR%:/out" ^
    -v "%CACHE_VOLUME%:/var/cache/retrolinux/mirror/offline:ro" ^
    archlinux/archlinux:latest bash -c " ^
        set -e
        rm -f /var/lib/pacman/db.lck 2>/dev/null || true
        pacman -Sy --noconfirm
        pacman --noconfirm -Sy archiso git sudo base-devel jq grub
        mkarchiso -v -w /work/ -o /out /profile/
    "

if %ERRORLEVEL% neq 0 (
    echo.
    call :rx_log ERROR "ISO build failed"
    exit /b 1
)

echo.
call :rx_log SUCCESS "ISO built successfully"
exit /b 0

:show_stats
for /f "delims=" %%i in ('dir /b "%OUTPUT_DIR%\*.iso" 2^>nul') do set "ISO_FILE=%%i"

if not defined ISO_FILE (
    call :rx_log WARN "No ISO file found in output directory"
    exit /b 0
)

echo.
call :rx_log INFO "Build completed"
call :rx_log INFO "Filename: %ISO_FILE%"

for %%a in ("%OUTPUT_DIR%\%ISO_FILE%") do set "SIZE_BYTES=%%~za"
set /a SIZE_GB100=%SIZE_BYTES% / 1073741824 * 100
call :rx_log INFO "Size: !SIZE_GB100:~0,-2!.!SIZE_GB100:~-2! GB (%SIZE_BYTES% bytes)"

for /f "delims=" %%i in ('certutil -hashfile "%OUTPUT_DIR%\%ISO_FILE%" SHA256 ^| findstr /v ":" ^| findstr /v "CertUtil"') do set "SHA256=%%i"
set "SHA256=!SHA256: =!"
call :rx_log INFO "SHA256: !SHA256!"

exit /b 0

:error_exit
echo.
call :rx_log ERROR "Build failed with %ERROR_COUNT% error(s)"
call :rx_log INFO "Common issues:"
call :rx_log INFO "Docker not installed: Install Docker Desktop"
call :rx_log INFO "Docker not running: Start Docker Desktop"
call :rx_log INFO "No internet: Check your connection"
call :rx_log INFO "Disk space: Ensure enough free space"
exit /b 1
