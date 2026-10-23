param(
  [string]$Project = 'C:\KcwDev\flutter_application_1'
)
$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
$Project = [System.IO.Path]::GetFullPath($Project)
if (!(Test-Path -LiteralPath (Join-Path $Project 'android'))) {
  throw "Flutter 프로젝트 루트를 찾을 수 없습니다: $Project"
}
foreach ($required in @('pubspec.yaml','lib\main.dart','packages\physical_lens_bridge\pubspec.yaml','packages\physical_lens_bridge\lib\physical_lens_bridge.dart')) {
  if (!(Test-Path -LiteralPath (Join-Path $source $required))) { throw "압축 해제 위치에 파일 없음: $required" }
}
$backupDir = Join-Path $Project ('.v9_1_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $Project 'pubspec.yaml') -Destination $backupDir -Force
Write-Host "Backup pubspec: $backupDir"
# Merge, not delete: preserve additional user's Dart source files.
$libDest = Join-Path $Project 'lib'
New-Item -ItemType Directory -Path $libDest -Force | Out-Null
Copy-Item -Path (Join-Path $source 'lib\*') -Destination $libDest -Recurse -Force
$pluginSource = Join-Path $source 'packages\physical_lens_bridge'
$pluginDest = Join-Path $Project 'packages\physical_lens_bridge'
New-Item -ItemType Directory -Path $pluginDest -Force | Out-Null
Copy-Item -Path (Join-Path $pluginSource '*') -Destination $pluginDest -Recurse -Force
Copy-Item -LiteralPath (Join-Path $source 'pubspec.yaml') -Destination (Join-Path $Project 'pubspec.yaml') -Force
Write-Host 'v9 camera code + local Android plugin + pubspec.yaml copied.'
Push-Location $Project
try {
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (code $LASTEXITCODE). Read the full output." }
  $configPath = Join-Path $Project '.dart_tool\package_config.json'
  if (!(Test-Path -LiteralPath $configPath)) { throw 'package_config.json not generated.' }
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $resolved = @($config.packages | ForEach-Object { $_.name })
  foreach ($name in @('camera_android', 'physical_lens_bridge')) {
    if ($name -notin $resolved) { throw "Package $name missing after pub get. Check pubspec/terminal output." }
    Write-Host "Resolved package: $name" -ForegroundColor Green
  }
  & flutter analyze
  if ($LASTEXITCODE -ne 0) { Write-Warning 'flutter analyze reported issues; see the output above.' }
} finally {
  Pop-Location
}
Write-Host 'Completed. If VS Code still shows red imports: Ctrl+Shift+P -> Dart: Restart Analysis Server.'
