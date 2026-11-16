# CA2213 false positive with System.Threading.Lock

A standalone, dependency-free reproduction using two classes, a `Timer`, and a
`MemoryStream`. The project builds a library; compilation alone reproduces the
diagnostic.

Verified on Windows with .NET SDK **11.0.100**, targeting **net11.0**, using C# 14.
The SDK version is pinned in `global.json`. There are no package references, and
`NuGet.Config` disables package sources so restoration uses the SDK's installed
framework references.

## Source files

The complete C# example is in [Repro.cs](Repro.cs). No decompilation is needed.

- [Project and build switch](Repro.csproj)
- [Analyzer configuration](.editorconfig)
- [Pinned SDK version](global.json)
- [Verification script](verify.ps1)
- [SDK issue description](ISSUE.md)
- [Recorded SDK environment](dotnet-info.txt)

## Reproduce

Run these commands from this directory:

```powershell
dotnet restore
dotnet build --no-restore -c Release -t:Rebuild -p:UseMonitor=false
```

The native `System.Threading.Lock` case fails with exit code **1** and:

```text
error CA2213: 'WorkerHost' contains field '_worker' that is of IDisposable type
'PeriodicWorker', but it is never disposed.
```

Change only the locking type through the existing MSBuild switch:

```powershell
dotnet build --no-restore -c Release -t:Rebuild -p:UseMonitor=true
```

The `object` / `Monitor` case succeeds with exit code **0**, zero warnings, and
zero errors. `.editorconfig` explicitly enables CA2213 as an error in both cases.

Alternatively, run the automated comparison:

```powershell
pwsh -File ./verify.ps1
```

The script verifies both expected exit codes and the CA2213 diagnostic, and saves
the complete build output in `verification/native-lock.log` and
`verification/monitor.log`.

## Relevant code shape

- `WorkerHost.Dispose()` unconditionally calls `_worker.Dispose()` first.
- A separate helper calls `_worker.Stop()` again inside `try`.
- The `finally` block disposes the owner's `MemoryStream`.
- `PeriodicWorker.Dispose()` calls `Stop()`, which disposes its `Timer` under the
  selected gate type.

Both builds contain the same disposal calls. Only the `Gate` alias changes.
Retain the helper and `try/finally` when reproducing this particular comparison:
inlining the helper or removing the `finally` changes the analyzer's result.

No analyzer suppression is used for CA2213, and the precise analyzer defect is
not assumed by this example.

The SDK issue draft is in [ISSUE.md](ISSUE.md). The complete SDK environment output is in [dotnet-info.txt](dotnet-info.txt).
