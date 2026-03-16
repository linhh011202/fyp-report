$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$diagramsDir = Join-Path $scriptDir "diagrams"
$imagesDir = Join-Path $scriptDir "images"

Write-Host "Converting Mermaid diagrams to images..."

$mmdcCommand = Get-Command mmdc -ErrorAction SilentlyContinue
if (-not $mmdcCommand) {
    Write-Error "mermaid-cli (mmdc) is not installed. Install it with: npm install -g @mermaid-js/mermaid-cli"
    exit 1
}

if (-not (Test-Path -Path $diagramsDir -PathType Container)) {
    Write-Error "Diagrams directory not found: $diagramsDir"
    exit 1
}

$null = New-Item -ItemType Directory -Path $imagesDir -Force

$diagramFiles = Get-ChildItem -Path $diagramsDir -Filter "*.mmd" -File | Sort-Object Name
if (-not $diagramFiles) {
    Write-Host "No Mermaid diagrams found in diagrams/"
    exit 0
}

$mmdcPath = $mmdcCommand.Source
$maxParallel = [Math]::Min($diagramFiles.Count, [Environment]::ProcessorCount)

Write-Host "Converting $($diagramFiles.Count) diagrams with $maxParallel parallel jobs..."

$failed = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$converted = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

$diagramFiles | ForEach-Object -ThrottleLimit $maxParallel -Parallel {
    $file = $_
    $outputPath = Join-Path $using:imagesDir ($file.BaseName + ".png")
    $mmdc = $using:mmdcPath
    $failedBag = $using:failed
    $convertedBag = $using:converted

    & $mmdc -i $file.FullName -o $outputPath -w 1600 -b white 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        $failedBag.Add($file.BaseName)
        Write-Host "FAILED: $($file.BaseName)" -ForegroundColor Red
    } else {
        $convertedBag.Add($file.BaseName)
        Write-Host "OK: $($file.BaseName)" -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    Write-Error "Failed to convert $($failed.Count) diagram(s): $($failed -join ', ')"
    exit 1
}

Write-Host "Conversion complete! $($converted.Count) images saved to images/"
