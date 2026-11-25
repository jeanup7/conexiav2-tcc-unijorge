@echo off
setlocal
set "CONEXIA_DEV=1"
set "FIREBASE_PROJECT_ID=conexiabeta2"
set "GOOGLE_APPLICATION_CREDENTIALS=%USERPROFILE%\Downloads\conexiabeta2-firebase-adminsdk-fbsvc-38fbe3275a.json"
if not "%~1"=="" set "GOOGLE_APPLICATION_CREDENTIALS=%~1"
set "CONEXIA_VISION_MODELS=%LOCALAPPDATA%\Conexia\vision-models"
if not exist "%~dp0.venv-vision\Scripts\python.exe" (
  echo Ambiente de visao ausente. Prepare as dependencias conforme backend\vision\NOTICE.txt.
  exit /b 1
)
if not exist "%CONEXIA_VISION_MODELS%\manifest.json" (
  echo Instale os modelos usando backend\install_vision_models.py.
  exit /b 1
)
if not exist "%GOOGLE_APPLICATION_CREDENTIALS%" (
  echo Credencial Firebase nao encontrada. Informe o caminho do JSON como argumento.
  exit /b 1
)
"%~dp0.venv-vision\Scripts\python.exe" "%~dp0server.py"
exit /b %ERRORLEVEL%
