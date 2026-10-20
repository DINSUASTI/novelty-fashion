$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo compilar el APK.'
    }

    $outputDir = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
    $source = Join-Path $outputDir 'app-release.apk'
    $destination = Join-Path $outputDir 'NoveltyFashion.apk'
    Copy-Item -LiteralPath $source -Destination $destination -Force

    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw 'La copia del APK no coincide con el archivo compilado.'
    }
    Write-Output $destination
} finally {
    Pop-Location
}