$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$projectPath = Join-Path $PSScriptRoot 'Repro.csproj'
$configPath = Join-Path $PSScriptRoot 'NuGet.Config'
$logDirectory = Join-Path $PSScriptRoot 'verification'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

Push-Location $PSScriptRoot
try {
    & dotnet restore $projectPath --configfile $configPath --verbosity quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Restore failed. Install the SDK version pinned in global.json.'
    }

    foreach ($buildCase in @(
        @{ Name = 'native-lock'; UseMonitor = 'false'; ExpectedExitCode = 1 },
        @{ Name = 'monitor'; UseMonitor = 'true'; ExpectedExitCode = 0 }
    )) {
        $buildOutput = @(& dotnet build $projectPath --no-restore -c Release -t:Rebuild "-p:UseMonitor=$($buildCase.UseMonitor)" --verbosity quiet 2>&1)
        $buildExitCode = $LASTEXITCODE
        $logPath = Join-Path $logDirectory ($buildCase.Name + '.log')
        [IO.File]::WriteAllLines($logPath, [string[]]$buildOutput)

        if ($buildExitCode -ne $buildCase.ExpectedExitCode) {
            throw "Unexpected exit code $buildExitCode for $($buildCase.Name). See $logPath."
        }

        if ($buildCase.Name -eq 'native-lock' -and ($buildOutput -join "`n") -notmatch "error CA2213:.*'_worker'") {
            throw "Native Lock failed without the expected CA2213 diagnostic. See $logPath."
        }

        Write-Output ("{0}: expected exit {1}; verified. Log: {2}" -f $buildCase.Name, $buildExitCode, $logPath)
    }
}
finally {
    Pop-Location
}
