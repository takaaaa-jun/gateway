# Use the shared generator through Git for Windows, even when sh is not on PATH.
$ErrorActionPreference = 'Stop'

$shellCommand = Get-Command sh.exe -ErrorAction SilentlyContinue
$shellPath = if ($shellCommand) { $shellCommand.Source } else { $null }

if (-not $shellPath) {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\sh.exe"
        "${env:ProgramFiles(x86)}\Git\bin\sh.exe"
        "$env:LOCALAPPDATA\Programs\Git\bin\sh.exe"
    )
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitRoot = Split-Path (Split-Path $gitCommand.Source -Parent) -Parent
        $candidates += Join-Path $gitRoot 'bin\sh.exe'
    }
    $shellPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

if (-not $shellPath) {
    Write-Error 'sh.exe was not found. Install Git for Windows or run scripts/add-app.sh in WSL.'
    exit 1
}

$generator = (Join-Path $PSScriptRoot 'add-app.sh').Replace('\', '/')
& $shellPath $generator @args
exit $LASTEXITCODE
