param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-Location $RepoRoot

Write-Host "Running repo hygiene checks..."
& "$PSScriptRoot\\validate_repo_hygiene.ps1" -RepoRoot $RepoRoot

Write-Host "Running Flutter static checks..."
flutter pub get
flutter analyze

Write-Host "Running Flutter tests..."
flutter test

Write-Host "Frontend pre-release checks passed."
