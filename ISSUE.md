# CA2213 false positive with System.Threading.Lock in a disposal call chain

## Describe the bug

CA2213 reports that a disposable field is never disposed when its implementation uses `System.Threading.Lock`, even though the containing type calls that field's `Dispose()` method unconditionally.

Changing only the gate type to `object`, so the same `lock` statement uses `Monitor`, removes the diagnostic. This reproduces in a standalone library with two classes, a `Timer`, and a `MemoryStream`, without any package references.

## Steps to reproduce

Using .NET SDK 11.0.100, create a directory with these four files.

`global.json`:

```json
{
  "sdk": {
    "version": "11.0.100",
    "rollForward": "disable"
  }
}
```

`Repro.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net11.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <LangVersion>14.0</LangVersion>
    <AnalysisLevel>latest-All</AnalysisLevel>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>
  <PropertyGroup Condition="'$(UseMonitor)' == 'true'">
    <DefineConstants>$(DefineConstants);USE_MONITOR</DefineConstants>
  </PropertyGroup>
</Project>
```

`.editorconfig`:

```ini
root = true

[*.cs]
dotnet_analyzer_diagnostic.severity = none
dotnet_diagnostic.CA1812.severity = none
dotnet_diagnostic.CA2213.severity = error
```

`Repro.cs`:

```csharp
#if USE_MONITOR
using Gate = System.Object;
#else
using Gate = System.Threading.Lock;
#endif

internal sealed class WorkerHost : IDisposable
{
    private readonly PeriodicWorker _worker = new();
    private readonly MemoryStream _buffer = new();

    public void Dispose()
    {
        _worker.Dispose();
        try
        {
            StopWorker();
        }
        finally
        {
            _buffer.Dispose();
        }
    }

    private void StopWorker() => _worker.Stop();
}

internal sealed class PeriodicWorker : IDisposable
{
    private readonly Gate _gate = new();
    private readonly Timer _timer = new(_ => { });

    public void Dispose() => Stop();

    public void Stop()
    {
        lock (_gate)
        {
            _timer.Dispose();
        }
    }
}
```

Restore and build with the native lock:

```powershell
dotnet restore
dotnet build --no-restore -c Release -t:Rebuild -p:UseMonitor=false
```

Then build the same project using the monitor gate:

```powershell
dotnet build --no-restore -c Release -t:Rebuild -p:UseMonitor=true
```

The complete repro also includes `verify.ps1`, which checks both expected exit codes and saves the build logs.

## Expected behavior

Both builds should succeed without CA2213. `WorkerHost.Dispose()` calls `_worker.Dispose()` first; `PeriodicWorker.Dispose()` calls `Stop()`, which disposes its timer. The owner's memory stream is disposed in the `finally` block.

## Actual behavior

The native `System.Threading.Lock` build reports:

```text
Repro.cs(9,37): error CA2213: 'WorkerHost' contains field '_worker' that is of IDisposable type 'PeriodicWorker', but it is never disposed. Change the Dispose method on 'WorkerHost' to call Close or Dispose on this field.
```

The build results on the same machine and SDK were:

| Build | Observed result |
| --- | --- |
| `UseMonitor=false` — `System.Threading.Lock` | CA2213 on `_worker`; exit code 1; elapsed 1.11 s |
| `UseMonitor=true` — `object` / `Monitor` | Success, zero warnings and errors; exit code 0; elapsed 0.31 s |

## Is this a regression?

Unknown. I have only tested SDK 11.0.100. Switching the gate type introduces the diagnostic within the same SDK; I have not compared SDK versions.

## Are there any workarounds?

Use an `object` gate instead of `System.Threading.Lock` (`-p:UseMonitor=true` in this repro).

## dotnet --info output

<details>
<summary>Full output</summary>

```text
.NET SDK:
 Version:           11.0.100
 Commit:            297acf930f
 Workload version:  11.0.100-manifests.5d612b92
 MSBuild version:   18.12.2-1.26529.118+297acf930

Runtime Environment:
 OS Name:     Windows
 OS Version:  10.0.26300
 OS Platform: Windows
 RID:         win-x64
 Base Path:   C:\Program Files\dotnet\sdk\11.0.100

.NET workloads installed:
 [android]
   Installation Source: VS 18.12.12405.243
   Manifest Version:    37.2.29/11.0.100
   Manifest Path:       C:\Program Files\dotnet\sdk-manifests\11.0.100\microsoft.net.sdk.android\37.2.29\WorkloadManifest.json
   Install Type:              Msi

 [maui-windows]
   Installation Source: VS 18.12.12405.243
   Manifest Version:    11.0.0/11.0.100
   Manifest Path:       C:\Program Files\dotnet\sdk-manifests\11.0.100\microsoft.net.sdk.maui\11.0.0\WorkloadManifest.json
   Install Type:              Msi

 [maccatalyst]
   Installation Source: VS 18.12.12405.243
   Manifest Version:    27.2.11039/11.0.100
   Manifest Path:       C:\Program Files\dotnet\sdk-manifests\11.0.100\microsoft.net.sdk.maccatalyst\27.2.11039\WorkloadManifest.json
   Install Type:              Msi

 [ios]
   Installation Source: VS 18.12.12405.243
   Manifest Version:    27.2.11039/11.0.100
   Manifest Path:       C:\Program Files\dotnet\sdk-manifests\11.0.100\microsoft.net.sdk.ios\27.2.11039\WorkloadManifest.json
   Install Type:              Msi

Configured to use workload sets when installing new manifests.
No workload sets are installed. Run "dotnet workload restore" to install a workload set.

Host:
  Version:      11.0.0
  Architecture: x64
  Commit:       297acf930f

.NET SDKs installed:
  11.0.100 [C:\Program Files\dotnet\sdk]

.NET runtimes installed:
  Microsoft.AspNetCore.App 3.1.32 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
  Microsoft.AspNetCore.App 8.0.34 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
  Microsoft.AspNetCore.App 9.0.23 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
  Microsoft.AspNetCore.App 10.0.15 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
  Microsoft.AspNetCore.App 11.0.0 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
  Microsoft.NETCore.App 3.1.32 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
  Microsoft.NETCore.App 8.0.34 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
  Microsoft.NETCore.App 9.0.23 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
  Microsoft.NETCore.App 10.0.15 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
  Microsoft.NETCore.App 11.0.0 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
  Microsoft.WindowsDesktop.App 3.1.32 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
  Microsoft.WindowsDesktop.App 8.0.34 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
  Microsoft.WindowsDesktop.App 9.0.23 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
  Microsoft.WindowsDesktop.App 10.0.15 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
  Microsoft.WindowsDesktop.App 11.0.0 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]

Other architectures found:
  x86   [C:\Program Files (x86)\dotnet]
    registered at [HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x86\InstallLocation]

Environment variables:
  Not set

global.json file:
  C:\dev\ca2233-repro\global.json

Learn more:
  https://aka.ms/dotnet/info

Download .NET:
  https://aka.ms/dotnet/download
```

</details>

## IDE version

Reproduced using the `dotnet` CLI; no IDE was involved.

## Other details

- Target framework: `net11.0`; language version: C# 14.
- SDK-bundled `Microsoft.CodeAnalysis.NetAnalyzers.dll` file version: `11.1.26.53018`.
- CA2213 is explicitly enabled as an error; it is not suppressed.
- The two builds contain identical disposal calls. Only the `Gate` alias changes.
- The exact analyzer defect has not been identified by this repro.
