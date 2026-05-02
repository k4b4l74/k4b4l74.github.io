Param()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Join-Path $scriptDir "..\\src\\main\\java"

if (-not (Test-Path -LiteralPath $root)) {
    Write-Error "Path not found: $root"
    exit 1
}

$rootPath = (Resolve-Path -LiteralPath $root).Path

$files = Get-ChildItem -LiteralPath $rootPath -Recurse -File -Filter *.java
$fileCount = $files.Count

$lineCount = 0
$stats = @{}

foreach ($file in $files) {
    $lines = (Get-Content -LiteralPath $file.FullName | Measure-Object -Line).Lines
    $lineCount += $lines

    $dir = $file.Directory.FullName
    while ($dir -and $dir.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $stats.ContainsKey($dir)) {
            $stats[$dir] = [PSCustomObject]@{ Files = 0; Lines = 0 }
        }
        $stats[$dir].Files++
        $stats[$dir].Lines += $lines

        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) {
            break
        }
        $dir = $parent
    }
}

Write-Host "Path: $rootPath"
Write-Host "Files: $fileCount"
Write-Host "Lines: $lineCount"
Write-Host ""

function Write-Children {
    param(
        [string]$Path,
        [string]$Prefix
    )

    $children = Get-ChildItem -LiteralPath $Path -Directory | Sort-Object Name
    $children = $children | Where-Object { $stats.ContainsKey($_.FullName) }

    for ($i = 0; $i -lt $children.Count; $i++) {
        $child = $children[$i]
        $isLast = ($i -eq ($children.Count - 1))
        if ($isLast) {
            $branch = "+- "
            $nextPrefix = $Prefix + "   "
        } else {
            $branch = "|- "
            $nextPrefix = $Prefix + "|  "
        }

        $childStats = $stats[$child.FullName]
        $name = Split-Path -Leaf $child.FullName
        Write-Host ($Prefix + $branch + $name + " [files=" + $childStats.Files + ", lines=" + $childStats.Lines + "]")

        Write-Children -Path $child.FullName -Prefix $nextPrefix
    }
}

$rootStats = $stats[$rootPath]
if (-not $rootStats) {
    $rootStats = [PSCustomObject]@{ Files = 0; Lines = 0 }
}
Write-Host ($rootPath + " [files=" + $rootStats.Files + ", lines=" + $rootStats.Lines + "]")
Write-Children -Path $rootPath -Prefix ""
