using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace AudioMixer
{
    internal sealed class DeviceInfo
    {
        public string Id;
        public string Name;
    }

    internal sealed class AppInfo
    {
        public string Key;
        public string Name;
        public string ExePath;
        public bool IsPlaying;
        public bool IsSystem;
        public float Volume = 1;
        public string Error;
    }

    internal sealed class Snapshot
    {
        public List<DeviceInfo> Devices = new List<DeviceInfo>();
        public string DefaultId = "";
        public List<AppInfo> Apps = new List<AppInfo>();
        /// Routes found in Windows that this app did not know about yet (app key -> device id).
        public Dictionary<string, string> Adopted = new Dictionary<string, string>();
        public bool RoutingAvailable;
        public string RoutingError;
        /// Set when the audio engine could not start at all.
        public string EngineError;
    }

    /// Owns every Core Audio object. All COM work happens on one background thread so a slow
    /// audio service can never freeze the window; the UI receives immutable snapshots.
    internal sealed class AudioEngine
    {
        public const string SystemSoundsKey = "system-sounds";

        private sealed class LiveApp
        {
            public AppInfo Info;
            public readonly HashSet<uint> Pids = new HashSet<uint>();
            public readonly List<ISimpleAudioVolume> Volumes = new List<ISimpleAudioVolume>();
            public readonly List<IAudioMeterInformation> Meters = new List<IAudioMeterInformation>();
        }

        public event Action<Snapshot> SnapshotReady;
        public event Action<Dictionary<string, float>> PeaksReady;

        private readonly Dictionary<string, string> assignments;
        private readonly Dictionary<uint, string> applied = new Dictionary<uint, string>();
        /// Processes Windows refused to move, and when; retried after a pause.
        private readonly Dictionary<uint, DateTime> failed = new Dictionary<uint, DateTime>();
        private readonly Dictionary<string, string> routeErrors = new Dictionary<string, string>();
        private readonly Dictionary<string, LiveApp> live = new Dictionary<string, LiveApp>();
        private readonly List<object> sessionObjects = new List<object>();
        private readonly Dictionary<uint, string> pathCache = new Dictionary<uint, string>();
        private readonly Dictionary<string, string> nameCache = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        private readonly Queue<Action> commands = new Queue<Action>();
        private readonly AutoResetEvent wake = new AutoResetEvent(false);
        private readonly uint ownPid = (uint)Process.GetCurrentProcess().Id;
        private Thread thread;
        private volatile bool stopping;
        /// False while the window is hidden or minimised: no meters, and slower rescans.
        public volatile bool Foreground = true;
        private bool rescan;

        private IMMDeviceEnumerator enumerator;
        private AudioPolicyConfig policy;
        private string policyError;

        public AudioEngine(Dictionary<string, string> savedAssignments)
        {
            assignments = new Dictionary<string, string>(savedAssignments);
        }

        public void Start()
        {
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Name = "AudioEngine";
            thread.SetApartmentState(ApartmentState.MTA);
            thread.Start();
        }

        public void Stop()
        {
            stopping = true;
            wake.Set();
            if (thread != null) thread.Join(2000);
        }

        // ---- Commands from the UI thread ----

        public void Assign(string key, string deviceId)
        {
            Post(delegate
            {
                if (string.IsNullOrEmpty(deviceId)) assignments.Remove(key); else assignments[key] = deviceId;
                routeErrors.Remove(key);
                LiveApp app;
                if (policy != null && live.TryGetValue(key, out app))
                {
                    foreach (uint pid in app.Pids)
                    {
                        failed.Remove(pid);
                        Apply(key, app.Info.Name, pid, deviceId ?? "");
                        // A refused "back to default" must not be retried as if it were a route.
                        if (string.IsNullOrEmpty(deviceId)) { applied[pid] = ""; failed.Remove(pid); }
                    }
                }
                rescan = true;
            });
        }

        public void SetVolume(string key, float value)
        {
            Post(delegate
            {
                LiveApp app;
                if (!live.TryGetValue(key, out app)) return;
                Guid context = Guid.Empty;
                foreach (ISimpleAudioVolume volume in app.Volumes) volume.SetMasterVolume(value, ref context);
                app.Info.Volume = value;
            });
        }

        public void SetDefaultOutput(string deviceId)
        {
            Post(delegate
            {
                IPolicyConfig config = (IPolicyConfig)new PolicyConfigClientCom();
                try
                {
                    int console = config.SetDefaultEndpoint(deviceId, 0);
                    int multimedia = config.SetDefaultEndpoint(deviceId, 1);
                    DebugLog.Write("default output -> " + deviceId + " hr=0x" + console.ToString("X8") + "/0x" + multimedia.ToString("X8"));
                }
                finally
                {
                    Marshal.ReleaseComObject(config);
                }
                rescan = true;
            });
        }

        public void ResetAllRoutes()
        {
            Post(delegate
            {
                assignments.Clear();
                routeErrors.Clear();
                if (policy != null)
                {
                    int hr = policy.ClearAll();
                    DebugLog.Write("reset all routes hr=0x" + hr.ToString("X8"));
                }
                applied.Clear();
                failed.Clear();
                rescan = true;
            });
        }

        /// Rescan now instead of waiting for the next tick.
        public void Refresh()
        {
            Post(delegate { rescan = true; });
        }

        private void Post(Action command)
        {
            lock (commands) commands.Enqueue(command);
            wake.Set();
        }

        // ---- Worker ----

        private void Run()
        {
            try
            {
                Initialize();
            }
            catch (Exception ex)
            {
                DebugLog.Write("engine failed to start: " + ex);
                Snapshot broken = new Snapshot();
                broken.EngineError = "Windows audio is not available: " + ex.Message;
                Action<Snapshot> report = SnapshotReady;
                if (report != null) report(broken);
                return;
            }

            DateTime nextScan = DateTime.MinValue;
            while (!stopping)
            {
                wake.WaitOne(Foreground ? 50 : 500);
                if (stopping) break;
                while (true)
                {
                    Action command;
                    lock (commands)
                    {
                        if (commands.Count == 0) break;
                        command = commands.Dequeue();
                    }
                    try { command(); }
                    catch (Exception ex) { DebugLog.Write("command failed: " + ex.Message); }
                }

                try
                {
                    if (rescan || DateTime.UtcNow >= nextScan)
                    {
                        rescan = false;
                        Snapshot snapshot = Scan();
                        nextScan = DateTime.UtcNow.AddSeconds(Foreground ? 1 : 3);
                        Action<Snapshot> handler = SnapshotReady;
                        if (handler != null) handler(snapshot);
                    }
                    else if (Foreground)
                    {
                        ReadPeaks();
                    }
                }
                catch (Exception ex)
                {
                    DebugLog.Write("scan failed: " + ex.Message);
                    nextScan = DateTime.UtcNow.AddSeconds(1);
                }
            }
            ReleaseSessions();
        }

        private void Initialize()
        {
            enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            policy = AudioPolicyConfig.TryCreate(out policyError);
            DebugLog.Write(policy != null
                ? "per-app routing available (" + policy.Variant + ")"
                : "per-app routing unavailable: " + policyError);
        }

        private void ReleaseSessions()
        {
            foreach (object item in sessionObjects)
            {
                try { Marshal.ReleaseComObject(item); } catch { }
            }
            sessionObjects.Clear();
            live.Clear();
        }

        private Snapshot Scan()
        {
            ReleaseSessions();
            Snapshot snapshot = new Snapshot();
            snapshot.RoutingAvailable = policy != null;
            snapshot.RoutingError = policyError;

            IMMDevice defaultDevice;
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out defaultDevice) >= 0 && defaultDevice != null)
            {
                string id;
                if (defaultDevice.GetId(out id) >= 0 && id != null) snapshot.DefaultId = id;
                Marshal.ReleaseComObject(defaultDevice);
            }

            IMMDeviceCollection collection;
            if (enumerator.EnumAudioEndpoints(0, 1, out collection) < 0 || collection == null) return snapshot;
            try
            {
                int count;
                collection.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    IMMDevice device;
                    if (collection.Item(i, out device) < 0 || device == null) continue;
                    try
                    {
                        string id;
                        if (device.GetId(out id) < 0 || id == null) continue;
                        DeviceInfo info = new DeviceInfo();
                        info.Id = id;
                        info.Name = FriendlyName(device) ?? "Output device";
                        snapshot.Devices.Add(info);
                        CollectSessions(device);
                    }
                    finally
                    {
                        Marshal.ReleaseComObject(device);
                    }
                }
            }
            finally
            {
                Marshal.ReleaseComObject(collection);
            }
            snapshot.Devices.Sort(delegate(DeviceInfo a, DeviceInfo b) { return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase); });

            Reconcile(snapshot);

            foreach (LiveApp app in live.Values)
            {
                string error;
                app.Info.Error = routeErrors.TryGetValue(app.Info.Key, out error) ? error : null;
                snapshot.Apps.Add(app.Info);
            }
            snapshot.Apps.Sort(delegate(AppInfo a, AppInfo b) { return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase); });
            return snapshot;
        }

        private static string FriendlyName(IMMDevice device)
        {
            IPropertyStore store;
            if (device.OpenPropertyStore(0, out store) < 0 || store == null) return null;
            try
            {
                PropertyKey key = new PropertyKey();
                key.FmtId = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0");   // PKEY_Device_FriendlyName
                key.Pid = 14;
                PropVariant value;
                if (store.GetValue(ref key, out value) < 0) return null;
                try
                {
                    return value.Vt == 31 && value.Pointer != IntPtr.Zero ? Marshal.PtrToStringUni(value.Pointer) : null;
                }
                finally
                {
                    Native.PropVariantClear(ref value);
                }
            }
            finally
            {
                Marshal.ReleaseComObject(store);
            }
        }

        private void CollectSessions(IMMDevice device)
        {
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object instance;
            if (device.Activate(ref iid, 23, IntPtr.Zero, out instance) < 0 || instance == null) return;
            IAudioSessionManager2 manager = (IAudioSessionManager2)instance;
            IAudioSessionEnumerator sessions = null;
            try
            {
                if (manager.GetSessionEnumerator(out sessions) < 0 || sessions == null) return;
                int count;
                sessions.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    IAudioSessionControl2 session;
                    if (sessions.GetSession(i, out session) < 0 || session == null) continue;
                    if (!AddSession(session)) Marshal.ReleaseComObject(session);
                }
            }
            finally
            {
                if (sessions != null) Marshal.ReleaseComObject(sessions);
                Marshal.ReleaseComObject(manager);
            }
        }

        /// Returns false when the session is not kept (the caller releases it).
        private bool AddSession(IAudioSessionControl2 session)
        {
            int state;
            if (session.GetState(out state) < 0 || state == 2) return false;   // expired

            bool system = session.IsSystemSoundsSession() == 0;
            uint pid;
            session.GetProcessId(out pid);
            if (!system && (pid == 0 || pid == ownPid)) return false;

            string key, name, path = null;
            if (system)
            {
                key = SystemSoundsKey;
                name = "System sounds";
            }
            else
            {
                path = PathFor(pid);
                if (path != null)
                {
                    key = path.ToLowerInvariant();
                    name = NameFor(path);
                }
                else
                {
                    string processName;
                    try { processName = Process.GetProcessById((int)pid).ProcessName; }
                    catch { return false; }   // the process has already exited
                    key = "process:" + processName.ToLowerInvariant();
                    name = processName;
                }
            }

            LiveApp app;
            if (!live.TryGetValue(key, out app))
            {
                app = new LiveApp();
                app.Info = new AppInfo();
                app.Info.Key = key;
                app.Info.Name = name;
                app.Info.ExePath = path;
                app.Info.IsSystem = system;
                live[key] = app;
                ISimpleAudioVolume first = session as ISimpleAudioVolume;
                float level;
                if (first != null && first.GetMasterVolume(out level) >= 0) app.Info.Volume = level;
            }
            if (state == 1) app.Info.IsPlaying = true;
            if (!system) app.Pids.Add(pid);

            ISimpleAudioVolume volume = session as ISimpleAudioVolume;
            if (volume != null) app.Volumes.Add(volume);
            IAudioMeterInformation meter = session as IAudioMeterInformation;
            if (meter != null) app.Meters.Add(meter);
            sessionObjects.Add(session);
            return true;
        }

        private string PathFor(uint pid)
        {
            string path;
            if (pathCache.TryGetValue(pid, out path)) return path;
            path = Native.ProcessPath(pid);
            if (path == null) return null;   // not cached: the pid may be reused by another app
            if (pathCache.Count > 512) pathCache.Clear();
            pathCache[pid] = path;
            return path;
        }

        private string NameFor(string path)
        {
            string name;
            if (nameCache.TryGetValue(path, out name)) return name;
            try
            {
                string description = FileVersionInfo.GetVersionInfo(path).FileDescription;
                name = string.IsNullOrWhiteSpace(description) ? null : description.Trim();
            }
            catch
            {
                name = null;
            }
            if (name == null) name = Path.GetFileNameWithoutExtension(path);
            nameCache[path] = name;
            return name;
        }

        /// Makes sure every process of every assigned app is on its device, and picks up
        /// routes that were set elsewhere (Windows Settings) so the window shows the truth.
        private void Reconcile(Snapshot snapshot)
        {
            HashSet<uint> seen = new HashSet<uint>();
            foreach (LiveApp app in live.Values)
            {
                foreach (uint pid in app.Pids) seen.Add(pid);
                if (policy == null || app.Info.IsSystem) continue;

                foreach (uint pid in app.Pids)
                {
                    string want;
                    assignments.TryGetValue(app.Info.Key, out want);
                    string done;
                    bool known = applied.TryGetValue(pid, out done);
                    if (want == null)
                    {
                        if (known) continue;
                        string current;
                        try { current = policy.GetOutput(pid); }
                        catch { current = ""; }
                        applied[pid] = current;
                        if (current.Length > 0)
                        {
                            assignments[app.Info.Key] = current;
                            snapshot.Adopted[app.Info.Key] = current;
                        }
                    }
                    else if (!known || done != want)
                    {
                        DateTime at;
                        if (failed.TryGetValue(pid, out at) && (DateTime.UtcNow - at).TotalSeconds < 10) continue;
                        Apply(app.Info.Key, app.Info.Name, pid, want);
                    }
                }

                bool anyFailed = false;
                foreach (uint pid in app.Pids) if (failed.ContainsKey(pid)) anyFailed = true;
                if (!anyFailed) routeErrors.Remove(app.Info.Key);
            }

            List<uint> gone = new List<uint>();
            foreach (uint pid in applied.Keys) if (!seen.Contains(pid)) gone.Add(pid);
            foreach (uint pid in gone) { applied.Remove(pid); pathCache.Remove(pid); }
            gone.Clear();
            foreach (uint pid in failed.Keys) if (!seen.Contains(pid)) gone.Add(pid);
            foreach (uint pid in gone) failed.Remove(pid);
        }

        private void Apply(string key, string name, uint pid, string deviceId)
        {
            int hr;
            try { hr = policy.SetOutput(pid, deviceId); }
            catch (Exception ex) { hr = Marshal.GetHRForException(ex); }
            if (hr < 0)
            {
                failed[pid] = DateTime.UtcNow;
                routeErrors[key] = "Windows refused to move this app (error 0x" + hr.ToString("X8") + ").";
                DebugLog.Write("route FAILED: " + name + " pid=" + pid + " -> " + deviceId + " hr=0x" + hr.ToString("X8"));
            }
            else
            {
                applied[pid] = deviceId;
                failed.Remove(pid);
                DebugLog.Write("route OK: " + name + " pid=" + pid + " -> " + (deviceId.Length == 0 ? "system default" : deviceId));
            }
        }

        private void ReadPeaks()
        {
            if (live.Count == 0) return;
            Action<Dictionary<string, float>> handler = PeaksReady;
            if (handler == null) return;
            Dictionary<string, float> peaks = new Dictionary<string, float>();
            foreach (LiveApp app in live.Values)
            {
                float max = 0;
                foreach (IAudioMeterInformation meter in app.Meters)
                {
                    float peak;
                    if (meter.GetPeakValue(out peak) >= 0 && peak > max) max = peak;
                }
                // The meter reports the level before the app's own volume; show what is heard.
                peaks[app.Info.Key] = Math.Min(1, max * app.Info.Volume);
            }
            handler(peaks);
        }

        /// One synchronous scan written as text; used by `AudioMixer.exe --selftest <file>`.
        public static string SelfTest(uint probePid, string probeDevice)
        {
            StringBuilder report = new StringBuilder();
            AudioEngine engine = new AudioEngine(new Dictionary<string, string>());
            engine.Initialize();
            report.AppendLine("routing: " + (engine.policy != null ? "available " + engine.policy.Variant : "UNAVAILABLE " + engine.policyError));
            Snapshot snapshot = engine.Scan();
            report.AppendLine("default: " + snapshot.DefaultId);
            foreach (DeviceInfo device in snapshot.Devices) report.AppendLine("device: " + device.Name + " | " + device.Id);
            foreach (AppInfo app in snapshot.Apps)
            {
                LiveApp item = engine.live[app.Key];
                string pids = "";
                string routes = "";
                foreach (uint pid in item.Pids)
                {
                    pids += pid + " ";
                    if (engine.policy != null) routes += "[" + engine.policy.GetOutput(pid) + "] ";
                }
                report.AppendLine("app: " + app.Name + " | playing=" + app.IsPlaying + " | volume=" + app.Volume.ToString("0.00")
                    + " | sessions=" + item.Volumes.Count + " meters=" + item.Meters.Count + " | pids=" + pids + "| persisted=" + routes + "| " + app.Key);
            }
            if (probePid != 0 && engine.policy != null)
            {
                string before = engine.policy.GetOutput(probePid);
                int set = engine.policy.SetOutput(probePid, probeDevice);
                string during = engine.policy.GetOutput(probePid);
                int restore = engine.policy.SetOutput(probePid, before);
                string after = engine.policy.GetOutput(probePid);
                report.AppendLine("probe pid " + probePid + ": before=[" + before + "] set=0x" + set.ToString("X8") + " during=[" + during
                    + "] restore=0x" + restore.ToString("X8") + " after=[" + after + "] roundtrip=" + (during == probeDevice && after == before));
            }
            engine.ReleaseSessions();
            return report.ToString();
        }
    }

    /// Append-only log at %LOCALAPPDATA%\AudioMixer\AudioMixer.log.
    internal static class DebugLog
    {
        private static readonly object Gate = new object();
        private static readonly string FilePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AudioMixer", "AudioMixer.log");

        public static string Location { get { return FilePath; } }

        public static void Write(string message)
        {
            try
            {
                lock (Gate)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
                    FileInfo info = new FileInfo(FilePath);
                    if (info.Exists && info.Length > 1024 * 1024) info.Delete();
                    File.AppendAllText(FilePath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message + Environment.NewLine);
                }
            }
            catch
            {
                // Logging must never take the app down.
            }
        }
    }
}
