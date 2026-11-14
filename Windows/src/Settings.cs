using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Microsoft.Win32;

namespace AudioMixer
{
    /// Preferences and per-app assignments, stored in %APPDATA%\AudioMixer\settings.txt
    /// as tab-separated lines so the file stays readable and needs no serializer.
    internal sealed class AppSettings
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunValue = "AudioMixer";
        public const string LoginArgument = "--login";

        private readonly string filePath;

        public readonly Dictionary<string, string> Assignments = new Dictionary<string, string>();
        public bool ShowSilentApps;
        public bool StartHidden = true;
        public bool TrayHintShown;
        /// Set for demo and screenshot runs so they can never overwrite real preferences.
        public bool ReadOnly;
        /// A settings file that exists but could not be read must not be replaced with defaults.
        private bool loadFailed;

        public AppSettings()
        {
            filePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AudioMixer", "settings.txt");
            Load();
        }

        private void Load()
        {
            try
            {
                if (!File.Exists(filePath)) return;
                foreach (string line in File.ReadAllLines(filePath, Encoding.UTF8))
                {
                    string[] parts = line.Split('\t');
                    if (parts.Length == 3 && parts[0] == "route") Assignments[parts[1]] = parts[2];
                    else if (parts.Length == 2 && parts[0] == "showSilentApps") ShowSilentApps = parts[1] == "1";
                    else if (parts.Length == 2 && parts[0] == "startHidden") StartHidden = parts[1] == "1";
                    else if (parts.Length == 2 && parts[0] == "trayHintShown") TrayHintShown = parts[1] == "1";
                }
            }
            catch (Exception ex)
            {
                loadFailed = true;
                DebugLog.Write("settings load failed: " + ex.Message);
            }
        }

        public void Save()
        {
            if (ReadOnly || loadFailed) return;
            try
            {
                StringBuilder text = new StringBuilder();
                text.AppendLine("showSilentApps\t" + (ShowSilentApps ? "1" : "0"));
                text.AppendLine("startHidden\t" + (StartHidden ? "1" : "0"));
                text.AppendLine("trayHintShown\t" + (TrayHintShown ? "1" : "0"));
                foreach (KeyValuePair<string, string> pair in Assignments) text.AppendLine("route\t" + pair.Key + "\t" + pair.Value);
                Directory.CreateDirectory(Path.GetDirectoryName(filePath));
                string temporary = filePath + ".tmp";
                File.WriteAllText(temporary, text.ToString(), Encoding.UTF8);
                if (File.Exists(filePath)) File.Replace(temporary, filePath, null);   // atomic swap
                else File.Move(temporary, filePath);
            }
            catch (Exception ex)
            {
                DebugLog.Write("settings save failed: " + ex.Message);
            }
        }

        // ---- Launch at login (per-user Run key, no admin rights needed) ----

        private static string ExecutablePath
        {
            get { return System.Reflection.Assembly.GetExecutingAssembly().Location; }
        }

        private static string RunCommand
        {
            get { return "\"" + ExecutablePath + "\" " + LoginArgument; }
        }

        public bool LaunchAtLogin
        {
            get
            {
                try
                {
                    using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey))
                    {
                        return key != null && key.GetValue(RunValue) != null;
                    }
                }
                catch
                {
                    return false;
                }
            }
        }

        /// Returns an error message, or null on success.
        public string SetLaunchAtLogin(bool enabled)
        {
            if (ReadOnly) return null;
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (enabled) key.SetValue(RunValue, RunCommand);
                    else key.DeleteValue(RunValue, false);
                }
                DebugLog.Write("launch at login " + (enabled ? "on" : "off"));
                return null;
            }
            catch (Exception ex)
            {
                DebugLog.Write("launch at login failed: " + ex.Message);
                return "Launch at login: " + ex.Message;
            }
        }

        /// If the app was moved after launch-at-login was turned on, point the entry at the new place.
        public void RepairLaunchAtLogin()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (key == null) return;
                    string current = key.GetValue(RunValue) as string;
                    if (current != null && current != RunCommand) key.SetValue(RunValue, RunCommand);
                }
            }
            catch
            {
            }
        }
    }
}
