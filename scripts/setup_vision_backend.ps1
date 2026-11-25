$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$pythonPath=Join-Path $repoRoot 'backend\.venv-vision\Scripts\python.exe'
Push-Location $repoRoot
try {
    if(!(Test-Path -LiteralPath $pythonPath)) {
        python -m venv backend/.venv-vision
        if($LASTEXITCODE -ne 0){throw 'Falha ao criar ambiente isolado.'}
    }
    & $pythonPath -m pip install -r backend/requirements-vision.txt
    if($LASTEXITCODE -ne 0){throw 'Falha ao instalar dependências.'}
    & $pythonPath backend/install_vision_models.py --directory (Join-Path $env:LOCALAPPDATA 'Conexia\vision-models')
    if($LASTEXITCODE -ne 0){throw 'Falha na validação dos modelos.'}
    Write-Output 'Ambiente pronto. Inicie com .\scripts\start_vision_backend.ps1'
} finally {Pop-Location}
