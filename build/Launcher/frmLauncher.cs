﻿using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.ComponentModel;
using System.Threading;
using Syringe;
using Syringe.Win32;

namespace Launcher
{
    public partial class frmLauncher : Form
    {
        private Thread InjectorThread;
        private string GamePath;

        public frmLauncher()
        {
            CreateInjectorThread();

            InitializeComponent();
        }

        private void CreateInjectorThread()
        {
            this.InjectorThread = new Thread(new ThreadStart(this.WaitAndInject));
            this.InjectorThread.IsBackground = true;
        }

        private string GetStartPath()
        {
            if (txtGamePath.TextLength > 0)
            {
                string currPath = Path.GetDirectoryName(txtGamePath.Text);
                if (Directory.Exists(currPath))
                {
                    return currPath;
                }
            }

            RegistryKey steamAppKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 49520");
            if (steamAppKey != null)
            {
                string installDir = (string)steamAppKey.GetValue("InstallLocation");
                if (!string.IsNullOrEmpty(installDir))
                {
                    string bl2Path = Path.GetFullPath(Path.Combine(installDir, "Binaries", "Win32"));
                    if (Directory.Exists(bl2Path))
                    {
                        return bl2Path;
                    }
                }
            }

            RegistryKey steamKey = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
            if (steamKey != null)
            {
                string steamPath = (string)steamKey.GetValue("SteamPath");
                if (!string.IsNullOrEmpty(steamPath))
                {
                    string bl2Path = Path.GetFullPath(Path.Combine(steamPath, "steamapps", "common", "Borderlands2", "Binaries", "Win32"));
                    if (Directory.Exists(bl2Path))
                    {
                        return bl2Path;
                    }
                }
            }

            return string.Empty;
        }

        private string GetAbsoluteGamePath()
        {
            string parent = GetStartPath();
            if (!string.IsNullOrEmpty(parent))
            {
                return Path.Combine(parent, "Borderlands2.exe");
            }
            else
            {
                return string.Empty;
            }
        }

        private void btnBrowse_Click(object sender, EventArgs e)
        {
            OpenFileDialog openFileDialog = new OpenFileDialog();
            openFileDialog.InitialDirectory = GetStartPath();
            openFileDialog.Filter = "Borderlands 2 (*.exe)|*.exe";
            DialogResult result = openFileDialog.ShowDialog();
            if (result == DialogResult.OK)
            {
                txtGamePath.Text = openFileDialog.FileName;
            }
        }

        private void ResetButton()
        {
            btnLaunch.Invoke(new MethodInvoker(
                delegate
                {
                    btnLaunch.Text = "Launch Game";
                    btnLaunch.Enabled = true;
                }
            ));
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SettingsStruct
        {
            public bool DisableAntiDebug;
            [CustomMarshalAs(CustomUnmanagedType.LPWStr)]
            public string BinPath;
        }

        private void WaitAndInject()
        {
            DateTime start = DateTime.Now;
            string procName = Path.GetFileNameWithoutExtension(this.GamePath);

            // Wait 30 seconds for Steam to get its shit together
            while((DateTime.Now - start).Seconds < 30)
            {
                Process[] procs = Process.GetProcessesByName(procName);
                Process bl2Proc = procs[0];
                if(bl2Proc == null)
                {
                    continue;
                }
           
                // We have found the process, so we can inject into it
                try
                {
                    Injector syringe = new Injector(bl2Proc);
                    syringe.InjectLibrary("BL2SDKDLL.dll");

                    SettingsStruct arg = new SettingsStruct() 
                    {
                        DisableAntiDebug = disableAntiDebugToolStripMenuItem.Checked,
                        BinPath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) + "\\"
                    };
                    syringe.CallExport("BL2SDKDLL.dll", "InitializeSDK", arg);
                }
                catch(Win32Exception e)
                {
                    MessageBox.Show("Failed to inject SDK into Borderlands 2. Error Message = " + e.Message + ", Error Code = " + e.NativeErrorCode, "Failed to launch", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    bl2Proc.Kill();
                    ResetButton();
                    return;
                }
                catch(Exception e)
                {
                    MessageBox.Show("Failed to inject SDK into Borderlands 2. Error Message = " + e.Message, "Failed to launch", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    bl2Proc.Kill();
                    ResetButton();
                    return;
                }
                
                // Resume all the suspended threads
                foreach (ProcessThread thread in bl2Proc.Threads)
                {
                    IntPtr hThread = Imports.OpenThread(
                        ThreadAccessFlags.SuspendResume,
                        false,
                        (uint)thread.Id);

                    Imports.ResumeThread(hThread);
                    Imports.CloseHandle(hThread);
                }
                
                Application.Exit();
                return;
            }

            MessageBox.Show("Failed to find game process after 30 seconds", "Failed to launch", MessageBoxButtons.OK, MessageBoxIcon.Error);
            ResetButton();
        }

        private void btnLaunch_Click(object sender, EventArgs ea)
        {
            if (this.InjectorThread.ThreadState == System.Threading.ThreadState.Stopped)
            {
                // Need to remake the thread
                CreateInjectorThread();
            }

            string gamePath = txtGamePath.Text;
            if (!File.Exists(gamePath))
            {
                MessageBox.Show("Invalid path - could not find Borderlands 2.exe", "Failed to Launch", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (Process.GetProcessesByName(Path.GetFileNameWithoutExtension(gamePath)).Length > 0)
            {
                MessageBox.Show("Borderlands 2 is already running. Please close it before trying again.", "Failed to Launch", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            this.GamePath = gamePath;
            string gameDir = Path.GetDirectoryName(gamePath);

            STARTUPINFO lpStartupInfo = new STARTUPINFO();

            Environment.SetEnvironmentVariable("SteamGameId", "49520");
            Environment.SetEnvironmentVariable("SteamAppId", "49520");

            PROCESS_INFORMATION lpProcessInformation;

            bool result = Imports.CreateProcess(
                gamePath,
                "-nolauncher",
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                ProcessCreationFlags.CreateSuspended,
                IntPtr.Zero,
                gameDir,
                ref lpStartupInfo, 
                out lpProcessInformation);

            if (result)
            {
                btnLaunch.Enabled = false;
                btnLaunch.Text = "Injecting into Borderlands 2...";

                this.InjectorThread.Start();

                Imports.CloseHandle(lpProcessInformation.hProcess);
                Imports.CloseHandle(lpProcessInformation.hThread);
            }
            else
            {
                MessageBox.Show("Failed to launch Borderlands 2. Error Code = " + Marshal.GetLastWin32Error(), "Failed to Launch", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void frmLauncher_Load(object sender, EventArgs e)
        {
            txtGamePath.Text = GetAbsoluteGamePath();
        }

        private void disableAntiDebugToolStripMenuItem_Click(object sender, EventArgs e)
        {
            disableAntiDebugToolStripMenuItem.Checked = !disableAntiDebugToolStripMenuItem.Checked;
        }
    }
}
