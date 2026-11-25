param([string]$DeviceId = 'emulator-5554', [int]$Port = 8083)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$directory = Join-Path ([System.IO.Path]::GetTempPath()) ('conexia-onboarding-' + [guid]::NewGuid().ToString('N'))
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$node = (Get-Command node).Source
$firebase = Join-Path $env:APPDATA 'npm\node_modules\firebase-tools\lib\bin\firebase.js'
$python = (Get-Command python).Source
$flutter = (Get-Command flutter).Source
if ($Port -lt 1024 -or $Port -gt 65535 -or $Port -in @(9099,4409,4509)) { throw 'Escolha uma porta de API válida e diferente das portas dos emuladores.' }
foreach ($targetPort in @($Port,9099,4409,4509)) {
    if (Get-NetTCPConnection -State Listen -LocalPort $targetPort -ErrorAction SilentlyContinue) { throw "Porta $targetPort ocupada. Encerre a execução anterior antes de continuar." }
}
if (!(Test-Path -LiteralPath $firebase)) { throw 'Instale a Firebase CLI antes de executar este teste local.' }
& $adb -s $DeviceId get-state
if ($LASTEXITCODE -ne 0) { throw 'Inicie o emulador Android antes de executar.' }
New-Item -ItemType Directory -Path $directory | Out-Null
$keys = @('DATABASE_PATH','PORT','CONEXIA_DEV','FIREBASE_PROJECT_ID','GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_AUTH_EMULATOR_HOST','CONEXIA_MEDIA_BUCKET','CONEXIA_INTEGRATION_TEST','FIREBASE_CLI_DISABLE_UPDATE_CHECK','CONEXIA_REVIEW_REQUIRED')
$previous = @{}
foreach ($key in $keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
$authProcess = $null
$apiProcess = $null
Push-Location $repoRoot
try {
    $env:CONEXIA_DEV = '1'
    $env:CONEXIA_INTEGRATION_TEST = '1'
    # Auth/school regression only; not evidence of human-review validation.
    $env:CONEXIA_REVIEW_REQUIRED = '0'
    $env:FIREBASE_PROJECT_ID = 'demo-conexia-barema'
    $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
    $env:GOOGLE_APPLICATION_CREDENTIALS = ''
    $env:CONEXIA_MEDIA_BUCKET = ''
    $env:FIREBASE_CLI_DISABLE_UPDATE_CHECK = 'true'
    $env:DATABASE_PATH = Join-Path $directory 'test.sqlite3'
    $env:PORT = "$Port"
    $config = Join-Path $repoRoot 'firebase\emulators.json'
    $authProcess = Start-Process -FilePath $node -ArgumentList @('"' + $firebase + '"','emulators:start','--only','auth','--project','demo-conexia-barema','--config','"' + $config + '"') -WorkingDirectory $directory -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'auth.log') -RedirectStandardError (Join-Path $directory 'auth-error.log') -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        if ($authProcess.HasExited) { throw 'Auth Emulator encerrou. Confira auth-error.log.' }
        try {
            $null = Invoke-RestMethod 'http://127.0.0.1:9099/emulator/v1/projects/demo-conexia-barema/config' -TimeoutSec 1
            $ready = $true
            break
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (!$ready) { throw 'Auth Emulator não iniciou no prazo esperado.' }
    & $python (Join-Path $repoRoot 'backend\prepare_onboarding_test.py') --directory $directory --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar identidades locais de teste.' }
    $apiProcess = Start-Process -FilePath $python -ArgumentList @('"' + (Join-Path $repoRoot 'backend\server.py') + '"') -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'api.log') -RedirectStandardError (Join-Path $directory 'api-error.log') -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($apiProcess.HasExited) { throw 'API encerrou. Confira api-error.log.' }
        try {
            $health = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 1
            if ($health.isolatedIntegration -and $health.authEmulator) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (!$ready) { throw 'A API isolada não iniciou.' }
    foreach ($targetPort in @($Port,9099)) {
        & $adb -s $DeviceId reverse "tcp:$targetPort" "tcp:$targetPort"
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao conectar o Android aos serviços de teste.' }
    }
    & $flutter test integration_test/onboarding_android_test.dart -d $DeviceId "--dart-define-from-file=$(Join-Path $directory 'qa-defines.json')"
    if ($LASTEXITCODE -ne 0) { throw 'O fluxo integrado falhou. Confira os registros desta execução.' }
} finally {
    foreach ($process in @($apiProcess,$authProcess)) {
        if ($null -ne $process -and !$process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
    }
    foreach ($targetPort in @($Port,9099)) { & $adb -s $DeviceId reverse --remove "tcp:$targetPort" 2>$null }
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process') }
    Pop-Location
    Write-Output "Evidências do teste local: $directory"
}
