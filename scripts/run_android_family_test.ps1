param(
    [string]$DeviceId = 'emulator-5554',
    [int]$Port = 8081,
    [string]$CredentialsPath = (Join-Path $HOME 'Downloads\Conexia-acessos-dupla-vinculada.json'),
    [string]$ServiceAccountPath = (Join-Path $HOME 'Downloads\conexiabeta2-firebase-adminsdk-fbsvc-38fbe3275a.json')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('conexia-android-qa-' + [guid]::NewGuid().ToString('N'))
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$python = (Get-Command python).Source
$flutter = (Get-Command flutter).Source
if (!(Test-Path -LiteralPath $ServiceAccountPath)) { throw 'Credencial do servidor Firebase não encontrada.' }
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) { throw 'A porta da API de teste já está ocupada. Escolha outra porta.' }
& $adb -s $DeviceId get-state
if ($LASTEXITCODE -ne 0) { throw 'Conecte um dispositivo ou inicie o emulador antes de executar.' }
& $python (Join-Path $repoRoot 'backend\prepare_android_test.py') --database (Join-Path $repoRoot 'backend\conexia.sqlite3') --credentials $CredentialsPath --directory $testDirectory --port $Port
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar o ambiente isolado.' }
$variables = @('DATABASE_PATH','PORT','CONEXIA_DEV','FIREBASE_PROJECT_ID','GOOGLE_APPLICATION_CREDENTIALS','CONEXIA_MEDIA_BUCKET','CONEXIA_INTEGRATION_TEST','CONEXIA_REVIEW_REQUIRED')
$previous = @{}
foreach ($key in $variables) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
$apiProcess = $null
Push-Location $repoRoot
try {
    $env:DATABASE_PATH = Join-Path $testDirectory 'test.sqlite3'
    $env:PORT = "$Port"
    $env:CONEXIA_DEV = '1'
    $env:CONEXIA_INTEGRATION_TEST = '1'
    # This older scenario covers family/social regression; review has its own suite.
    $env:CONEXIA_REVIEW_REQUIRED = '0'
    $env:CONEXIA_MEDIA_BUCKET = ''
    $env:FIREBASE_PROJECT_ID = 'conexiabeta2'
    $env:GOOGLE_APPLICATION_CREDENTIALS = $ServiceAccountPath
    $apiScript = Join-Path $repoRoot 'backend\server.py'
    $apiProcess = Start-Process -FilePath $python -ArgumentList @('"' + $apiScript + '"') -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $testDirectory 'api.log') -RedirectStandardError (Join-Path $testDirectory 'api-error.log') -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($apiProcess.HasExited) { throw 'A API de teste encerrou. Confira api-error.log na pasta de execução.' }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1
            if ($health.status -eq 'ok' -and $health.firebase -and $health.isolatedIntegration) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (!$ready) { throw 'A API de teste não iniciou no prazo esperado.' }
    & $adb -s $DeviceId reverse "tcp:$Port" "tcp:$Port"
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível conectar o dispositivo à API local.' }
    & $flutter test integration_test/family_android_test.dart -d $DeviceId "--dart-define-from-file=$(Join-Path $testDirectory 'qa-defines.json')"
    if ($LASTEXITCODE -ne 0) { throw 'O teste Android falhou; não considere a validação concluída.' }
} finally {
    if ($null -ne $apiProcess -and !$apiProcess.HasExited) { Stop-Process -Id $apiProcess.Id -ErrorAction SilentlyContinue }
    & $adb -s $DeviceId reverse --remove "tcp:$Port" 2>$null
    foreach ($key in $variables) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
    Pop-Location
    Write-Output "Arquivos desta execução: $testDirectory"
}
