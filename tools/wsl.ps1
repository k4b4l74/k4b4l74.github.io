param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Command
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDir '.settings'
$settings = @{}

if (Test-Path $settingsPath) {
  foreach ($line in Get-Content -LiteralPath $settingsPath) {
    $trim = $line.Trim()
    if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
    $parts = $trim.Split('=', 2)
    if ($parts.Count -lt 2) { continue }
    $key = $parts[0].Trim()
    $val = $parts[1].Trim()
    if ($val.StartsWith('"') -and $val.EndsWith('"')) {
      $val = $val.Substring(1, $val.Length - 2)
    }
    $settings[$key] = $val
  }
}

$wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
if ($settings.ContainsKey('WSL_EXE') -and $settings['WSL_EXE']) {
  $wslExe = $settings['WSL_EXE']
}

if (-not $Command -or $Command.Count -eq 0) {
  Write-Host 'Usage: tools\wsl.ps1 <command>'
  Write-Host 'Example: tools\wsl.ps1 docker ps'
  exit 1
}

$distro = $null
if ($settings.ContainsKey('WSL_DISTRO') -and $settings['WSL_DISTRO']) {
  $distro = $settings['WSL_DISTRO']
}

if (-not $distro) {
  $rawList = & $wslExe -l -q 2>$null
  $clean = $rawList | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -ne '' }
  $distro = $clean | Select-Object -First 1
}

if ($distro) {
  & $wslExe -d $distro -- @Command
  exit $LASTEXITCODE
}

& $wslExe -- @Command
exit $LASTEXITCODE
