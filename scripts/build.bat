@echo off
rem Release build for one client: scripts\build.bat <client> <dev|prod> [apk|appbundle] [extra flutter args]
rem Backend settings come from config\<env>.json. The output is copied to dist\ArenaBook-<client>-<version>[-dev].<apk|aab>.
setlocal
cd /d "%~dp0.."

set "CLIENT=%~1"
set "ENV=%~2"
set "TARGET=%~3"
if "%TARGET%"=="" set "TARGET=apk"
if "%CLIENT%"=="" goto usage
if not exist "lib\app\config\clients\%CLIENT%.dart" (
  echo Unknown client "%CLIENT%".
  goto usage
)
if /i not "%ENV%"=="dev" if /i not "%ENV%"=="prod" (
  echo Unknown environment "%ENV%". Use dev or prod.
  goto usage
)
if not exist "config\%ENV%.json" (
  echo Missing config\%ENV%.json: copy config\example.json and fill in the project's URL and anon key.
  exit /b 1
)
set "SUFFIX="
if /i "%ENV%"=="dev" set "SUFFIX=-dev"
if /i not "%TARGET%"=="apk" if /i not "%TARGET%"=="appbundle" (
  echo Unknown target "%TARGET%". Use apk or appbundle; iOS builds need a Mac ^(scripts/build.sh^).
  goto usage
)

for /f "tokens=2" %%v in ('findstr /b "version:" pubspec.yaml') do set "VERSION=%%v"
shift & shift & shift
set "EXTRA="
:collect
if "%~1"=="" goto build
set "EXTRA=%EXTRA% %1"
shift
goto collect

:build
echo Building %CLIENT% %TARGET% v%VERSION% against %ENV% ...
call flutter build %TARGET% --release --flavor %CLIENT% --dart-define-from-file=config\%ENV%.json%EXTRA%
if errorlevel 1 exit /b 1

if not exist dist mkdir dist
if /i "%TARGET%"=="apk" (
  set "SRC=build\app\outputs\flutter-apk\app-%CLIENT%-release.apk"
  set "OUT=dist\ArenaBook-%CLIENT%-%VERSION%%SUFFIX%.apk"
) else (
  set "SRC=build\app\outputs\bundle\%CLIENT%Release\app-%CLIENT%-release.aab"
  set "OUT=dist\ArenaBook-%CLIENT%-%VERSION%%SUFFIX%.aab"
)
copy /y "%SRC%" "%OUT%" >nul || exit /b 1
echo Done: %OUT%
exit /b 0

:usage
echo Usage: scripts\build.bat ^<client^> ^<dev^|prod^> [apk^|appbundle] [extra flutter args]
echo Clients:
for %%f in (lib\app\config\clients\*.dart) do if /i not "%%~nf"=="client_config" echo   %%~nf
exit /b 1
