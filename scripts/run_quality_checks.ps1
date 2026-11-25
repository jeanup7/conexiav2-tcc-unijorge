param([string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ('conexia-quality-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use uma pasta nova para preservar os resultados anteriores.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$previousCoverageFile = $env:COVERAGE_FILE
Push-Location $repoRoot
try {
    $env:COVERAGE_FILE = Join-Path $OutputDirectory 'backend.coverage'
    python -m coverage run --rcfile=backend/coverage.ini -m unittest discover -s backend 2>&1 | Tee-Object -FilePath (Join-Path $OutputDirectory 'backend-tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'A suíte Python falhou. Instale backend/requirements-dev.txt se coverage estiver ausente.' }
    python -m coverage report --rcfile=backend/coverage.ini 2>&1 | Tee-Object -FilePath (Join-Path $OutputDirectory 'backend-coverage.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao medir cobertura Python.' }
    python -m coverage json --rcfile=backend/coverage.ini -o (Join-Path $OutputDirectory 'backend-coverage.json')
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao exportar cobertura Python.' }
    flutter test --coverage "--coverage-path=$(Join-Path $OutputDirectory 'flutter-coverage.info')" 2>&1 | Tee-Object -FilePath (Join-Path $OutputDirectory 'flutter-tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'A suíte Flutter falhou.' }
    flutter analyze 2>&1 | Tee-Object -FilePath (Join-Path $OutputDirectory 'flutter-analyze.log')
    if ($LASTEXITCODE -ne 0) { throw 'A análise estática encontrou problemas.' }
} finally {
    [Environment]::SetEnvironmentVariable('COVERAGE_FILE', $previousCoverageFile, 'Process')
    Pop-Location
    Write-Output "Resultados da execução: $OutputDirectory"
}
