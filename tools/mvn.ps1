param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Command
)

function Import-DotEnvFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmedLine = $line.Trim()
    if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) {
      continue
    }

    $parts = $line.Split('=', 2)
    if ($parts.Count -lt 2) {
      continue
    }

    $name = $parts[0].Trim()
    if ($name -eq '') {
      continue
    }

    if (Test-Path -LiteralPath "Env:$name") {
      continue
    }

    $value = $parts[1].Trim()
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    Set-Item -Path "Env:$name" -Value $value
  }
}

function Test-ItFlagPresent {
  param(
    [string[]]$CommandArgs
  )

  foreach ($arg in $CommandArgs) {
    $normalizedArg = if ($null -ne $arg) { $arg.Trim().Trim('"') } else { $arg }
    if ($normalizedArg -match '^-D[^=\s]+\.it(?:=|$)') {
      return $true
    }
  }

  return $false
}

function Test-HasExplicitMavenGoal {
  param(
    [string[]]$CommandArgs
  )

  $optionsWithValue = @(
    '-f', '--file',
    '-pl', '--projects',
    '-rf', '--resume-from',
    '-s', '--settings',
    '-gs', '--global-settings',
    '-t', '--toolchains',
    '-P', '--activate-profiles',
    '-amd', '--also-make-dependents',
    '-am', '--also-make',
    '-l', '--log-file',
    '-T', '--threads'
  )

  for ($index = 0; $index -lt $CommandArgs.Count; $index++) {
    $arg = $CommandArgs[$index]
    if ($null -eq $arg) {
      continue
    }

    $normalizedArg = $arg.Trim().Trim('"')
    if ($optionsWithValue -contains $normalizedArg) {
      $index++
      continue
    }

    if (-not $normalizedArg.StartsWith('-')) {
      return $true
    }
  }

  return $false
}

function Test-DockerProxyPing {
  $attempts = 5
  $timeoutSec = 3
  $delayMs = 1000
  $lastContent = $null
  $lastError = $null

  for ($attempt = 1; $attempt -le $attempts; $attempt++) {
    try {
      $response = Invoke-WebRequest -Uri 'http://localhost:2376/_ping' -Method Get -TimeoutSec $timeoutSec -UseBasicParsing
      $content = if ($null -ne $response.Content) { $response.Content.Trim() } else { '' }
      if ($content -eq 'OK') {
        return [PSCustomObject]@{
          IsOk = $true
          Content = $content
          Error = $null
        }
      }
      $lastContent = $content
      $lastError = $null
    } catch {
      $lastContent = $null
      $lastError = $_.Exception.Message
    }

    if ($attempt -lt $attempts) {
      Start-Sleep -Milliseconds $delayMs
    }
  }

  return [PSCustomObject]@{
    IsOk = $false
    Content = $lastContent
    Error = $lastError
  }
}

function Get-DockerProxyFailureReason {
  param(
    $ProbeResult
  )

  if ($ProbeResult.Error) {
    return $ProbeResult.Error
  }

  if ($ProbeResult.Content) {
    return "unexpected response '$($ProbeResult.Content)'"
  }

  return 'no response'
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
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

$mavenCmd = if ($settings.ContainsKey('MAVEN_CMD') -and $settings['MAVEN_CMD']) { $settings['MAVEN_CMD'] } else { 'mvn' }

if ($settings.ContainsKey('JAVA_HOME') -and $settings['JAVA_HOME']) {
  $env:JAVA_HOME = $settings['JAVA_HOME']
}

$props = @()
if ($settings.ContainsKey('IDEA_VERSION') -and $settings['IDEA_VERSION']) { $props += "-Didea.version=$($settings['IDEA_VERSION'])" }
if ($settings.ContainsKey('MAVEN_EXT_CLASS_PATH') -and $settings['MAVEN_EXT_CLASS_PATH']) { $props += "-Dmaven.ext.class.path=$($settings['MAVEN_EXT_CLASS_PATH'])" }
if ($settings.ContainsKey('MAVEN_REPO_LOCAL') -and $settings['MAVEN_REPO_LOCAL']) { $props += "-Dmaven.repo.local=$($settings['MAVEN_REPO_LOCAL'])" }
if ($settings.ContainsKey('JANSI_PASSTHROUGH') -and $settings['JANSI_PASSTHROUGH']) { $props += "-Djansi.passthrough=$($settings['JANSI_PASSTHROUGH'])" }
if ($settings.ContainsKey('STYLE_COLOR') -and $settings['STYLE_COLOR']) { $props += "-Dstyle.color=$($settings['STYLE_COLOR'])" }

if (-not $Command -or $Command.Count -eq 0) {
  if ($settings.ContainsKey('MAVEN_DEFAULT_ARGS') -and $settings['MAVEN_DEFAULT_ARGS']) {
    $Command = $settings['MAVEN_DEFAULT_ARGS'].Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
  }
}

if (-not $Command -or $Command.Count -eq 0) {
  Write-Host 'Usage: tools\mvn.bat <args>'
  Write-Host 'Example: tools\mvn.bat test'
  exit 1
}

Import-DotEnvFile -Path (Join-Path $repoRoot '.env')

if (Test-ItFlagPresent -CommandArgs $Command) {
  if (-not (Test-HasExplicitMavenGoal -CommandArgs $Command)) {
    Write-Host 'Integration-test flags detected in Maven arguments.' -ForegroundColor Yellow
    Write-Host 'No explicit Maven goal was provided.' -ForegroundColor Yellow
    Write-Host 'This project defaults to `spring-boot:run`, so the application would start instead of running tests.' -ForegroundColor Yellow
    Write-Host 'Use a command such as:' -ForegroundColor Yellow
    Write-Host '.\tools\mvn.bat -Drag.it=true -Dllm.it=true -Dtest=SynchronizeBySourceIdIT test' -ForegroundColor Yellow
    exit 1
  }

  Write-Host 'Integration-test flags detected in Maven arguments.'
  Write-Host 'Checking integration-test Docker proxy: GET http://localhost:2376/_ping'
  $dockerProxyPing = Test-DockerProxyPing
  if ($dockerProxyPing.IsOk) {
    Write-Host 'Integration-test Docker proxy check result: OK' -ForegroundColor Green
  } else {
    $reason = Get-DockerProxyFailureReason -ProbeResult $dockerProxyPing
    Write-Host "Integration-test Docker proxy check result: KO ($reason)" -ForegroundColor Yellow
    Write-Host 'Integration-test Docker proxy is not reachable at http://localhost:2376/_ping.' -ForegroundColor Yellow
    Write-Host 'Run this in WSL, then retry:' -ForegroundColor Yellow
    Write-Host 'sudo -v' -ForegroundColor Yellow
    Write-Host 'sudo nohup socat TCP-LISTEN:2376,bind=127.0.0.1,fork UNIX-CONNECT:/var/run/docker.sock >/tmp/wsl-docker-proxy.log 2>&1 < /dev/null &' -ForegroundColor Yellow
    exit 1
  }
}

Push-Location $repoRoot
& $mavenCmd @props @Command
$exitCode = $LASTEXITCODE
Pop-Location
exit $exitCode
