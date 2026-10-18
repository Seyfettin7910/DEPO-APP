@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo === Depo Takip - Web derleme ===
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter bulunamadi. Once Flutter SDK kurun: https://docs.flutter.dev/get-started/install/windows
  pause
  exit /b 1
)
call flutter create --platforms=web .
call flutter pub get
if errorlevel 1 goto hata
call dart run sqflite_common_ffi_web:setup --force
if errorlevel 1 goto hata
call flutter build web --release
if errorlevel 1 goto hata
echo.
echo Bitti! build\web klasoru hazir. Bu klasoru https://app.netlify.com/drop sayfasina surukleyin.
start "" "build\web"
pause
exit /b 0
:hata
echo.
echo Derleme sirasinda hata oldu. Yukaridaki mesaji Claudea gonderin.
pause
exit /b 1
