: << 'CMDBLOCK'
@echo off
setlocal EnableDelayedExpansion
REM Polyglot wrapper: runs .sh scripts cross-platform
REM Usage: run-hook.cmd <script-name> [args...]
REM The script should be in the same directory as this wrapper

REM Strategy 1: Find Git root via 'git --exec-path', then locate bash
for /f "tokens=*" %%i in ('git --exec-path 2^>nul') do set "GIT_EXEC_PATH=%%i"
if defined GIT_EXEC_PATH (
    for %%d in ("!GIT_EXEC_PATH!\..\..\..") do set "GIT_ROOT=%%~fd"
    if exist "!GIT_ROOT!\usr\bin\bash.exe" (
        "!GIT_ROOT!\usr\bin\bash.exe" -l "%~dp0%~1" %2 %3 %4 %5 %6 %7 %8 %9
        exit /b
    )
    if exist "!GIT_ROOT!\bin\bash.exe" (
        "!GIT_ROOT!\bin\bash.exe" -l "%~dp0%~1" %2 %3 %4 %5 %6 %7 %8 %9
        exit /b
    )
)

REM Strategy 2: Find Git root via 'where git', then locate bash
for /f "tokens=*" %%i in ('where git 2^>nul') do (
    for %%d in ("%%~dpi..") do set "GIT_ROOT2=%%~fd"
    if exist "!GIT_ROOT2!\usr\bin\bash.exe" (
        "!GIT_ROOT2!\usr\bin\bash.exe" -l "%~dp0%~1" %2 %3 %4 %5 %6 %7 %8 %9
        exit /b
    )
    if exist "!GIT_ROOT2!\bin\bash.exe" (
        "!GIT_ROOT2!\bin\bash.exe" -l "%~dp0%~1" %2 %3 %4 %5 %6 %7 %8 %9
        exit /b
    )
)

REM Strategy 3: Fallback to bash in PATH
where bash >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    bash -l "%~dp0%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b
)

echo ERROR: Git Bash not found. Please install Git for Windows.
exit /b 1
CMDBLOCK

# Unix shell runs from here
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
"${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
