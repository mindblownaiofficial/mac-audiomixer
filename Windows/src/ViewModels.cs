using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Media;

namespace AudioMixer
{
    internal abstract class Observable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        protected void Raise(string name)
        {
            PropertyChangedEventHandler handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
    }

    /// One row in a device picker. Id "" is "System default".
    internal sealed class DeviceOption
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Glyph { get; set; }

        /// Picks a Segoe icon for a device from its name.
        public static string GlyphFor(string name)
        {
            string n = (name ?? "").ToLowerInvariant();
            if (n.Length == 0) return "";   // equalizer: follows the system default
            if (ContainsAny(n, "headphone", "headset", "hyperx", "airpods", "buds", "beats", "earphone")) return "";
            if (ContainsAny(n, "display", "hdmi", "monitor", "arzopa", "lg ", "dell", "samsung", "nvidia", "tv")) return "";
            if (ContainsAny(n, "mixer", "maono", "focusrite", "scarlett", "interface", "rode", "elgato", "voicemeeter", "virtual", "cable")) return "";
            return "";   // speakers
        }

        private static bool ContainsAny(string text, params string[] words)
        {
            foreach (string word in words) if (text.Contains(word)) return true;
            return false;
        }
    }

    internal sealed class AppViewModel : Observable
    {
        private static readonly Brush PlayingBrush = Frozen(Color.FromRgb(0x1D, 0xD9, 0xF9));
        private static readonly Brush SilentBrush = Frozen(Color.FromArgb(0x59, 0xFF, 0xFF, 0xFF));

        private readonly MixerViewModel owner;
        private string name;
        private bool isPlaying;
        private string deviceId = "";
        private double volume = 100;
        private double level;
        private string error;
        private ImageSource icon;
        private DateTime userVolumeAt = DateTime.MinValue;

        public AppViewModel(MixerViewModel owner, AppInfo info)
        {
            this.owner = owner;
            Key = info.Key;
            ExePath = info.ExePath;
            IsSystem = info.IsSystem;
            name = info.Name;
            volume = Math.Round(info.Volume * 100);
        }

        public string Key { get; private set; }
        public string ExePath { get; private set; }
        public bool IsSystem { get; private set; }
        public ObservableCollection<DeviceOption> Options { get { return owner.AppOptions; } }

        public string Name
        {
            get { return name; }
            set { if (name != value) { name = value; Raise("Name"); } }
        }

        public ImageSource Icon
        {
            get { return icon; }
            set { icon = value; Raise("Icon"); Raise("IconVisibility"); Raise("FallbackIconVisibility"); }
        }

        public Visibility IconVisibility { get { return icon != null ? Visibility.Visible : Visibility.Collapsed; } }
        public Visibility FallbackIconVisibility { get { return icon == null ? Visibility.Visible : Visibility.Collapsed; } }
        public string FallbackGlyph { get { return IsSystem ? "" : ""; } }

        public bool IsPlaying
        {
            get { return isPlaying; }
            set
            {
                if (isPlaying == value) return;
                isPlaying = value;
                Raise("IsPlaying"); Raise("StatusText"); Raise("DotBrush");
            }
        }

        public string StatusText { get { return isPlaying ? "Playing" : "Silent"; } }
        public Brush DotBrush { get { return isPlaying ? PlayingBrush : SilentBrush; } }

        /// Bound two-way to the picker. "" means system default.
        public string DeviceId
        {
            get { return deviceId; }
            set
            {
                // The picker pushes null while its list is being rebuilt; that is not a choice.
                if (value == null || value == deviceId || owner.IsRebuilding) return;
                deviceId = value;
                RaiseRouting();
                owner.OnUserAssigned(this, value);
            }
        }

        public void SetDeviceFromEngine(string value)
        {
            if (deviceId == value) return;
            deviceId = value;
            RaiseRouting();
        }

        public void RaiseRouting()
        {
            Raise("DeviceId"); Raise("RoutedVisibility"); Raise("MissingVisibility");
        }

        public bool IsRouted { get { return deviceId.Length > 0 && owner.HasDevice(deviceId); } }
        public Visibility RoutedVisibility { get { return IsRouted ? Visibility.Visible : Visibility.Collapsed; } }
        public Visibility MissingVisibility { get { return deviceId.Length > 0 && !owner.HasDevice(deviceId) ? Visibility.Visible : Visibility.Collapsed; } }
        public Visibility PickerVisibility { get { return IsSystem || !owner.RoutingAvailable ? Visibility.Collapsed : Visibility.Visible; } }

        /// 0...100, bound two-way to the slider.
        public double Volume
        {
            get { return volume; }
            set
            {
                double clamped = Math.Max(0, Math.Min(100, value));
                if (Math.Abs(clamped - volume) < 0.01) return;
                volume = clamped;
                userVolumeAt = DateTime.UtcNow;
                Raise("Volume"); Raise("VolumeText");
                owner.OnUserVolume(this, (float)(clamped / 100));
            }
        }

        public void SetVolumeFromEngine(float value)
        {
            // Ignore the engine briefly after a drag so the thumb does not jump back.
            if ((DateTime.UtcNow - userVolumeAt).TotalSeconds < 1.5) return;
            double percent = Math.Round(value * 100);
            if (Math.Abs(percent - volume) < 0.5) return;
            volume = percent;
            Raise("Volume"); Raise("VolumeText");
        }

        public string VolumeText { get { return ((int)Math.Round(volume)) + "%"; } }

        public double Level
        {
            get { return level; }
            set { if (Math.Abs(level - value) > 0.0005) { level = value; Raise("Level"); } }
        }

        public string Error
        {
            get { return error; }
            set { if (error != value) { error = value; Raise("Error"); Raise("ErrorVisibility"); } }
        }

        public Visibility ErrorVisibility { get { return string.IsNullOrEmpty(error) ? Visibility.Collapsed : Visibility.Visible; } }

        public void RaisePickerVisibility() { Raise("PickerVisibility"); }

        private static Brush Frozen(Color color)
        {
            SolidColorBrush brush = new SolidColorBrush(color);
            brush.Freeze();
            return brush;
        }
    }

    /// Everything the window binds to. Lives on the UI thread.
    internal sealed class MixerViewModel : Observable
    {
        private readonly AppSettings settings;
        private readonly Dictionary<string, AppViewModel> byKey = new Dictionary<string, AppViewModel>();
        private List<DeviceInfo> devices = new List<DeviceInfo>();
        private string defaultId = "";
        private string statusMessage;
        private bool routingAvailable = true;
        private bool hasSnapshot;

        public MixerViewModel(AppSettings settings)
        {
            this.settings = settings;
            Devices = new ObservableCollection<DeviceOption>();
            AppOptions = new ObservableCollection<DeviceOption>();
            Playing = new ObservableCollection<AppViewModel>();
            Silent = new ObservableCollection<AppViewModel>();
            AllApps = new List<AppViewModel>();
            DeviceOption system = new DeviceOption();
            system.Id = ""; system.Name = "System default"; system.Glyph = DeviceOption.GlyphFor("");
            AppOptions.Add(system);
        }

        public Action<string, string> AssignRequested;
        public Action<string, float> VolumeRequested;
        public Action<string> DefaultRequested;
        public Action<AppViewModel> IconRequested;

        public ObservableCollection<DeviceOption> Devices { get; private set; }
        public ObservableCollection<DeviceOption> AppOptions { get; private set; }
        public ObservableCollection<AppViewModel> Playing { get; private set; }
        public ObservableCollection<AppViewModel> Silent { get; private set; }
        /// Every known app, including hidden silent ones (the tray menu reads this).
        public List<AppViewModel> AllApps { get; private set; }

        public bool IsRebuilding { get; private set; }
        public bool RoutingAvailable { get { return routingAvailable; } }
        public List<DeviceInfo> DeviceList { get { return devices; } }

        public bool HasDevice(string id)
        {
            foreach (DeviceInfo device in devices) if (device.Id == id) return true;
            return false;
        }

        public string DeviceName(string id)
        {
            foreach (DeviceInfo device in devices) if (device.Id == id) return device.Name;
            return null;
        }

        public string DefaultDeviceId
        {
            get { return defaultId; }
            set
            {
                if (value == null || value == defaultId || IsRebuilding) return;
                defaultId = value;
                RaiseDefault();
                if (DefaultRequested != null) DefaultRequested(value);
            }
        }

        public string DefaultGlyph { get { return DeviceOption.GlyphFor(DeviceName(defaultId) ?? "speaker"); } }

        private void RaiseDefault()
        {
            Raise("DefaultDeviceId"); Raise("DefaultGlyph");
        }

        public bool ShowSilentApps
        {
            get { return settings.ShowSilentApps; }
            set
            {
                if (settings.ShowSilentApps == value) return;
                settings.ShowSilentApps = value;
                settings.Save();
                Raise("ShowSilentApps");
                RebuildSections();
            }
        }

        public string StatusMessage
        {
            get { return statusMessage; }
            set { statusMessage = value; Raise("StatusMessage"); Raise("StatusVisibility"); }
        }

        public Visibility StatusVisibility { get { return string.IsNullOrEmpty(statusMessage) ? Visibility.Collapsed : Visibility.Visible; } }

        public string Subtitle
        {
            get
            {
                int routed = 0;
                foreach (AppViewModel app in AllApps) if (app.IsRouted) routed++;
                return routed == 0 ? "Nothing routed" : routed + " routed";
            }
        }

        public Visibility PlayingVisibility { get { return Playing.Count > 0 ? Visibility.Visible : Visibility.Collapsed; } }
        public Visibility SilentVisibility { get { return Silent.Count > 0 ? Visibility.Visible : Visibility.Collapsed; } }
        public Visibility EmptyVisibility { get { return hasSnapshot && Playing.Count == 0 && Silent.Count == 0 ? Visibility.Visible : Visibility.Collapsed; } }

        // ---- From the pickers and sliders ----

        public void OnUserAssigned(AppViewModel app, string deviceId)
        {
            Assign(app.Key, deviceId);
        }

        public void Assign(string key, string deviceId)
        {
            if (string.IsNullOrEmpty(deviceId)) settings.Assignments.Remove(key); else settings.Assignments[key] = deviceId;
            settings.Save();
            AppViewModel app;
            if (byKey.TryGetValue(key, out app)) app.SetDeviceFromEngine(deviceId ?? "");
            if (AssignRequested != null) AssignRequested(key, deviceId ?? "");
            Raise("Subtitle");
            RebuildSections();
        }

        public void OnUserVolume(AppViewModel app, float value)
        {
            if (VolumeRequested != null) VolumeRequested(app.Key, value);
        }

        public void ClearAssignments()
        {
            settings.Assignments.Clear();
            settings.Save();
            foreach (AppViewModel app in AllApps) app.SetDeviceFromEngine("");
            Raise("Subtitle");
            RebuildSections();
        }

        // ---- From the engine ----

        public void Apply(Snapshot snapshot)
        {
            hasSnapshot = true;
            if (snapshot.EngineError != null)
            {
                StatusMessage = snapshot.EngineError;
                Raise("EmptyVisibility");
                return;
            }
            if (routingAvailable != snapshot.RoutingAvailable)
            {
                routingAvailable = snapshot.RoutingAvailable;
                foreach (AppViewModel app in AllApps) app.RaisePickerVisibility();
            }
            if (!routingAvailable && statusMessage == null)
            {
                StatusMessage = "This version of Windows does not allow per-app output devices. Volumes still work.";
            }

            bool adopted = false;
            foreach (KeyValuePair<string, string> pair in snapshot.Adopted)
            {
                if (settings.Assignments.ContainsKey(pair.Key)) continue;
                settings.Assignments[pair.Key] = pair.Value;
                adopted = true;
            }
            if (adopted) settings.Save();

            bool devicesChanged = !SameDevices(devices, snapshot.Devices);
            devices = snapshot.Devices;
            if (devicesChanged) RebuildDeviceOptions();

            if (defaultId != snapshot.DefaultId || devicesChanged)
            {
                defaultId = snapshot.DefaultId;
                RaiseDefault();
            }

            HashSet<string> present = new HashSet<string>();
            foreach (AppInfo info in snapshot.Apps)
            {
                present.Add(info.Key);
                AppViewModel app;
                if (!byKey.TryGetValue(info.Key, out app))
                {
                    app = new AppViewModel(this, info);
                    byKey[info.Key] = app;
                    if (IconRequested != null) IconRequested(app);
                }
                app.Name = info.Name;
                app.IsPlaying = info.IsPlaying;
                app.Error = info.Error;
                app.SetVolumeFromEngine(info.Volume);
                string assigned;
                app.SetDeviceFromEngine(settings.Assignments.TryGetValue(info.Key, out assigned) ? assigned : "");
                if (devicesChanged) app.RaiseRouting();
            }

            List<string> gone = new List<string>();
            foreach (string key in byKey.Keys) if (!present.Contains(key)) gone.Add(key);
            foreach (string key in gone) byKey.Remove(key);

            AllApps = new List<AppViewModel>(byKey.Values);
            AllApps.Sort(delegate(AppViewModel a, AppViewModel b) { return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase); });
            RebuildSections();
            Raise("Subtitle");
        }

        public void ApplyPeaks(Dictionary<string, float> peaks)
        {
            foreach (AppViewModel app in AllApps)
            {
                float peak;
                peaks.TryGetValue(app.Key, out peak);
                double next = Math.Max(peak, app.Level * 0.8);
                app.Level = next < 0.001 ? 0 : next;
            }
        }

        private static bool SameDevices(List<DeviceInfo> a, List<DeviceInfo> b)
        {
            if (a.Count != b.Count) return false;
            for (int i = 0; i < a.Count; i++) if (a[i].Id != b[i].Id || a[i].Name != b[i].Name) return false;
            return true;
        }

        private void RebuildDeviceOptions()
        {
            IsRebuilding = true;
            try
            {
                Devices.Clear();
                while (AppOptions.Count > 1) AppOptions.RemoveAt(AppOptions.Count - 1);
                foreach (DeviceInfo device in devices)
                {
                    DeviceOption option = new DeviceOption();
                    option.Id = device.Id; option.Name = device.Name; option.Glyph = DeviceOption.GlyphFor(device.Name);
                    Devices.Add(option);
                    AppOptions.Add(option);
                }
            }
            finally
            {
                IsRebuilding = false;
            }
            // Re-announce the selections the pickers lost while their lists were empty.
            RaiseDefault();
            foreach (AppViewModel app in AllApps) app.RaiseRouting();
        }

        /// Shown apps: playing, routed, or everything when "Silent apps" is on.
        private void RebuildSections()
        {
            List<AppViewModel> playing = new List<AppViewModel>();
            List<AppViewModel> silent = new List<AppViewModel>();
            foreach (AppViewModel app in AllApps)
            {
                if (app.IsPlaying) playing.Add(app);
                else if (settings.ShowSilentApps || settings.Assignments.ContainsKey(app.Key)) silent.Add(app);
            }
            Sync(Playing, playing);
            Sync(Silent, silent);
            Raise("PlayingVisibility"); Raise("SilentVisibility"); Raise("EmptyVisibility");
        }

        /// Updates a bound list in place so untouched cards keep their state (open menus, drags).
        private static void Sync(ObservableCollection<AppViewModel> target, List<AppViewModel> wanted)
        {
            for (int i = target.Count - 1; i >= 0; i--) if (!wanted.Contains(target[i])) target.RemoveAt(i);
            for (int i = 0; i < wanted.Count; i++)
            {
                if (i < target.Count && ReferenceEquals(target[i], wanted[i])) continue;
                int existing = target.IndexOf(wanted[i]);
                if (existing >= 0) target.Move(existing, i); else target.Insert(i, wanted[i]);
            }
        }
    }
}
