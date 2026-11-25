param([int]$Port=8080, [string]$PythonPath='', [string]$ModelsPath=(Join-Path $env:LOCALAPPDATA 'Conexia\vision-models'))
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
if(!$PythonPath){$PythonPath=Join-Path $repoRoot 'backend\.venv-vision\Scripts\python.exe'}
if(!(Test-Path -LiteralPath $PythonPath)){throw 'Prepare o ambiente com .\scripts\setup_vision_backend.ps1'}
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) { throw 'A porta já está ocupada. Encerre a API anterior ou escolha outra porta.' }
if (!(Test-Path -LiteralPath (Join-Path $ModelsPath 'manifest.json'))) { throw 'Instale primeiro os modelos com backend/install_vision_models.py.' }
$keys=@('CONEXIA_VISION_MODELS','CONEXIA_DEV','FIREBASE_PROJECT_ID','GOOGLE_APPLICATION_CREDENTIALS','PORT')
$previous=@{}
foreach($key in $keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
Push-Location $repoRoot
try{
    $env:CONEXIA_VISION_MODELS=$ModelsPath
    $env:CONEXIA_DEV='1'
    $env:FIREBASE_PROJECT_ID='conexiabeta2'
    $env:GOOGLE_APPLICATION_CREDENTIALS=Join-Path $HOME 'Downloads\conexiabeta2-firebase-adminsdk-fbsvc-38fbe3275a.json'
    $env:PORT="$Port"
    & $PythonPath backend/server.py
    if($LASTEXITCODE -ne 0){throw 'A API experimental não iniciou. Confira ambiente e dependências.'}
}finally{
    foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
    Pop-Location
}
