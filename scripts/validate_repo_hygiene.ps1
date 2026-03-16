param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-Location $RepoRoot

$blockedTrackedFiles = @(
  "android/app/google-services.json",
  "ios/Runner/GoogleService-Info.plist"
)

$tracked = git ls-files
foreach ($path in $blockedTrackedFiles) {
  if (($tracked -contains $path) -and (Test-Path $path)) {
    throw "Blocked sensitive file is tracked in git: $path"
  }
}

$secretPatterns = @(
  "AIza[0-9A-Za-z\\-_]{35}",
  "-----BEGIN (RSA |EC |)PRIVATE KEY-----",
  "ghp_[0-9A-Za-z]{36,}",
  "xox[baprs]-[0-9A-Za-z-]{10,}"
)

$scanTargets = @("lib", "android", "ios", "web")
foreach ($pattern in $secretPatterns) {
  $hits = rg -n --hidden --glob "!build/**" --glob "!.dart_tool/**" --glob "!.git/**" -- $pattern $scanTargets
  if ($LASTEXITCODE -eq 0 -and $hits) {
    throw "Potential secret pattern detected: $pattern`n$hits"
  }
}

Write-Host "Repo hygiene checks passed."
