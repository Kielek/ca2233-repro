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
