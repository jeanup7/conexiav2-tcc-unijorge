@echo off
setlocal
set "CONEXIA_DEV=1"
set "FIREBASE_PROJECT_ID=conexiabeta2"
set "GOOGLE_APPLICATION_CREDENTIALS=%USERPROFILE%\Downloads\conexiabeta2-firebase-adminsdk-fbsvc-38fbe3275a.json"
if not "%~1"=="" set "GOOGLE_APPLICATION_CREDENTIALS=%~1"
if not exist "%GOOGLE_APPLICATION_CREDENTIALS%" (
  echo Credencial Firebase nao encontrada. Informe o caminho do JSON como argumento.
  exit /b 1
)
python "%~dp0server.py"
exit /b %ERRORLEVEL%
