# InstaPaste: one key screenshots. Saved to a folder and copied, ready to paste.

$ErrorActionPreference = 'Stop'

try {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace InstaPaste
{
    public static class Theme
    {
        public static Color Bg = Color.FromArgb(20, 20, 24);
        public static Color Card = Color.FromArgb(30, 30, 36);
        public static Color Line = Color.FromArgb(44, 44, 54);
        public static Color Key = Color.FromArgb(42, 42, 52);
        public static Color Text = Color.FromArgb(242, 242, 245);
        public static Color Muted = Color.FromArgb(150, 150, 165);
        public static Color Accent = Color.FromArgb(124, 92, 255);
        public static Color AccentHover = Color.FromArgb(143, 116, 255);

        public static GraphicsPath Round(RectangleF r, float radius)
        {
            float d = radius * 2;
            GraphicsPath p = new GraphicsPath();
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static Bitmap Logo(int size)
        {
            Bitmap bmp = new Bitmap(size, size);
            float s = size / 32f;
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (GraphicsPath p = Round(new RectangleF(1 * s, 1 * s, 30 * s, 30 * s), 8 * s))
                using (Brush bg = new LinearGradientBrush(new Rectangle(0, 0, size, size), Color.FromArgb(150, 120, 255), Color.FromArgb(100, 70, 235), 45f))
                    g.FillPath(bg, p);
                using (Pen w = new Pen(Color.White, 2.6f * s))
                {
                    w.StartCap = LineCap.Round; w.EndCap = LineCap.Round; w.LineJoin = LineJoin.Round;
                    g.DrawLines(w, new PointF[] { new PointF(8 * s, 14 * s), new PointF(8 * s, 8 * s), new PointF(14 * s, 8 * s) });
                    g.DrawLines(w, new PointF[] { new PointF(18 * s, 24 * s), new PointF(24 * s, 24 * s), new PointF(24 * s, 18 * s) });
                }
                g.FillEllipse(Brushes.White, 13 * s, 13 * s, 6 * s, 6 * s);
            }
            return bmp;
        }

        public static string KeyName(Keys k)
        {
            if (k == Keys.None) return "Not set";
            string s = "";
            if ((k & Keys.Control) != 0) s += "Ctrl + ";
            if ((k & Keys.Shift) != 0) s += "Shift + ";
            if ((k & Keys.Alt) != 0) s += "Alt + ";
            Keys c = k & Keys.KeyCode;
            string n;
            switch (c)
            {
                case Keys.Snapshot: n = "Print Screen"; break;
                case Keys.Scroll: n = "Scroll Lock"; break;
                case Keys.Pause: n = "Pause"; break;
                case Keys.Next: n = "Page Down"; break;
                case Keys.Prior: n = "Page Up"; break;
                case Keys.Return: n = "Enter"; break;
                case Keys.Back: n = "Backspace"; break;
                case Keys.Capital: n = "Caps Lock"; break;
                case Keys.Apps: n = "Menu"; break;
                case Keys.Oemtilde: n = "`"; break;
                case Keys.OemMinus: n = "-"; break;
                case Keys.Oemplus: n = "="; break;
                case Keys.Oemcomma: n = ","; break;
                case Keys.OemPeriod: n = "."; break;
                default:
                    if (c >= Keys.D0 && c <= Keys.D9) n = ((int)(c - Keys.D0)).ToString();
                    else if (c >= Keys.NumPad0 && c <= Keys.NumPad9) n = "Num " + ((int)(c - Keys.NumPad0)).ToString();
                    else n = c.ToString();
                    break;
            }
            return s + n;
        }
    }

    public static class Settings
    {
        public static Keys Full = Keys.F9;
        public static Keys Area = Keys.Snapshot;
        public static string Folder;
        public static bool Copy = true, Save = true, Popup = true;
        public static bool FirstRun;

        static string FilePath
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "InstaPaste", "settings.txt"); }
        }

        public static void Load()
        {
            Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "InstaPaste");
            if (!File.Exists(FilePath)) { FirstRun = true; return; }
            foreach (string line in File.ReadAllLines(FilePath))
            {
                int i = line.IndexOf('=');
                if (i < 0) continue;
                string k = line.Substring(0, i), v = line.Substring(i + 1);
                try
                {
                    if (k == "Full") Full = (Keys)int.Parse(v);
                    if (k == "Area") Area = (Keys)int.Parse(v);
                    if (k == "Folder" && v.Length > 0) Folder = v;
                    if (k == "Copy") Copy = v == "1";
                    if (k == "Save") Save = v == "1";
                    if (k == "Popup") Popup = v == "1";
                }
                catch { }
            }
        }

        public static void Store()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
            File.WriteAllLines(FilePath, new string[] {
                "Full=" + (int)Full, "Area=" + (int)Area, "Folder=" + Folder,
                "Copy=" + (Copy ? "1" : "0"), "Save=" + (Save ? "1" : "0"), "Popup=" + (Popup ? "1" : "0")
            });
        }

        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        public static bool StartupOn
        {
            get
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue("InstaPaste") != null;
            }
            set
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (value)
                        k.SetValue("InstaPaste", "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + App.ScriptPath + "\"");
                    else
                        k.DeleteValue("InstaPaste", false);
                }
            }
        }
    }

    public static class Hook
    {
        delegate IntPtr Proc(int n, IntPtr w, IntPtr l);
        [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, Proc fn, IntPtr mod, uint tid);
        [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
        [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);

        static Proc proc;
        static IntPtr handle;
        static int swallowed = -1;
        public static Func<Keys, bool> OnKey;

        public static void Start()
        {
            proc = Callback;
            handle = SetWindowsHookEx(13, proc, GetModuleHandle("user32.dll"), 0);
        }

        public static void Stop()
        {
            if (handle != IntPtr.Zero) UnhookWindowsHookEx(handle);
        }

        public static bool IsModifier(Keys c)
        {
            return c == Keys.ShiftKey || c == Keys.LShiftKey || c == Keys.RShiftKey
                || c == Keys.ControlKey || c == Keys.LControlKey || c == Keys.RControlKey
                || c == Keys.Menu || c == Keys.LMenu || c == Keys.RMenu || c == Keys.LWin || c == Keys.RWin;
        }

        static bool Down(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

        static IntPtr Callback(int n, IntPtr w, IntPtr l)
        {
            if (n >= 0)
            {
                int msg = w.ToInt32();
                int vk = Marshal.ReadInt32(l);
                if (msg == 0x100 || msg == 0x104)
                {
                    if (vk == swallowed) return new IntPtr(1);
                    Keys k = (Keys)vk;
                    if (!IsModifier(k))
                    {
                        if (Down(0x11)) k |= Keys.Control;
                        if (Down(0x10)) k |= Keys.Shift;
                        if (Down(0x12)) k |= Keys.Alt;
                    }
                    if (OnKey != null && OnKey(k)) { swallowed = vk; return new IntPtr(1); }
                }
                else if (msg == 0x101 || msg == 0x105)
                {
                    if (vk == swallowed) { swallowed = -1; return new IntPtr(1); }
                }
            }
            return CallNextHookEx(handle, n, w, l);
        }
    }

    public static class App
    {
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        public static string ScriptPath;
        const string ShowEventName = "InstaPaste_ShowSettings";

        public static void Run(string scriptPath)
        {
            try { if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) SetProcessDPIAware(); }
            catch { try { SetProcessDPIAware(); } catch { } }

            bool created;
            Mutex mutex = new Mutex(true, "InstaPaste_SingleInstance", out created);
            if (!created)
            {
                try { EventWaitHandle.OpenExisting(ShowEventName).Set(); } catch { }
                return;
            }
            EventWaitHandle showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);

            ScriptPath = scriptPath;
            Settings.Load();
            if (Settings.StartupOn) Settings.StartupOn = true;

            Application.EnableVisualStyles();
            MainWindow main = new MainWindow();
            ThreadPool.RegisterWaitForSingleObject(showEvent, delegate {
                try { main.BeginInvoke((MethodInvoker)main.ShowSettings); } catch { }
            }, null, -1, false);
            Application.Run(main);
            GC.KeepAlive(mutex);
        }

        public static void Deliver(Bitmap bmp)
        {
            if (Settings.Save)
            {
                Directory.CreateDirectory(Settings.Folder);
                string name = "InstaPaste_" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss-fff") + ".png";
                bmp.Save(Path.Combine(Settings.Folder, name), ImageFormat.Png);
            }
            if (Settings.Copy)
            {
                DataObject data = new DataObject();
                data.SetImage(bmp);
                MemoryStream png = new MemoryStream();
                bmp.Save(png, ImageFormat.Png);
                data.SetData("PNG", false, png);
                try { Clipboard.SetDataObject(data, true, 10, 100); } catch { }
            }
            if (Settings.Popup)
                Toast.Show(Settings.Copy ? "Copied! Paste with Ctrl+V" : "Saved to folder");
        }
    }

    public class MainWindow : Form
    {
        NotifyIcon tray;
        SettingsForm settings;
        ToolStripMenuItem fullItem, areaItem;
        bool busy;

        public MainWindow()
        {
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.None;
            Opacity = 0;

            tray = new NotifyIcon();
            tray.Icon = Icon.FromHandle(Theme.Logo(32).GetHicon());
            tray.Text = "InstaPaste";
            tray.Visible = true;
            tray.MouseClick += delegate(object s, MouseEventArgs e) { if (e.Button == MouseButtons.Left) ShowSettings(); };

            ContextMenuStrip menu = new ContextMenuStrip();
            fullItem = new ToolStripMenuItem("", null, delegate { CaptureFull(); });
            areaItem = new ToolStripMenuItem("", null, delegate { CaptureArea(); });
            menu.Items.Add(fullItem);
            menu.Items.Add(areaItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Settings", null, delegate { ShowSettings(); });
            menu.Items.Add("Open screenshots folder", null, delegate { OpenFolder(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit InstaPaste", null, delegate { Close(); });
            menu.Opening += delegate {
                fullItem.Text = "Full screen   (" + Theme.KeyName(Settings.Full) + ")";
                areaItem.Text = "Pick an area   (" + Theme.KeyName(Settings.Area) + ")";
            };
            tray.ContextMenuStrip = menu;

            Hook.OnKey = HandleKey;
        }

        protected override void SetVisibleCore(bool value)
        {
            if (!IsHandleCreated) CreateHandle();
            base.SetVisibleCore(false);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Hook.Start();
            if (Settings.FirstRun)
            {
                Settings.Store();
                BeginInvoke((MethodInvoker)ShowSettings);
            }
            else
            {
                Toast.Show("InstaPaste is ready");
            }
        }

        bool HandleKey(Keys k)
        {
            if (KeyBox.Recorder != null)
            {
                if (Hook.IsModifier(k & Keys.KeyCode)) return false;
                KeyBox r = KeyBox.Recorder;
                BeginInvoke((MethodInvoker)delegate { r.SetKey(k); });
                return true;
            }
            if (k == Settings.Full) { BeginInvoke((MethodInvoker)CaptureFull); return true; }
            if (k == Settings.Area) { BeginInvoke((MethodInvoker)CaptureArea); return true; }
            return false;
        }

        public void ShowSettings()
        {
            if (settings == null || settings.IsDisposed) settings = new SettingsForm();
            settings.Show();
            if (settings.WindowState == FormWindowState.Minimized) settings.WindowState = FormWindowState.Normal;
            settings.Activate();
        }

        public static void OpenFolder()
        {
            Directory.CreateDirectory(Settings.Folder);
            System.Diagnostics.Process.Start("explorer.exe", "\"" + Settings.Folder + "\"");
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            Hook.Stop();
            tray.Visible = false;
            tray.Dispose();
            base.OnFormClosed(e);
        }

        void CaptureFull()
        {
            if (busy) return;
            busy = true;
            try
            {
                Rectangle b = Screen.FromPoint(Cursor.Position).Bounds;
                using (Bitmap bmp = Grab(b)) App.Deliver(bmp);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "InstaPaste"); }
            finally { busy = false; }
        }

        void CaptureArea()
        {
            if (busy) return;
            busy = true;
            try
            {
                Rectangle vs = SystemInformation.VirtualScreen;
                using (Bitmap snap = Grab(vs))
                using (SelectForm f = new SelectForm(snap, vs))
                {
                    f.ShowDialog();
                    if (f.Result != null)
                        using (Bitmap r = f.Result) App.Deliver(r);
                }
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "InstaPaste"); }
            finally { busy = false; }
        }

        static Bitmap Grab(Rectangle r)
        {
            Bitmap bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
                g.CopyFromScreen(r.X, r.Y, 0, 0, r.Size, CopyPixelOperation.SourceCopy);
            return bmp;
        }
    }

    public class SettingsForm : Form
    {
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        float scale = 1f;
        List<Rectangle> cards = new List<Rectangle>();
        Font fBody, fSmall, fCaps, fTitle;
        Label pathLabel;

        int S(float v) { return (int)Math.Round(v * scale); }

        public SettingsForm()
        {
            using (Graphics g = CreateGraphics()) scale = g.DpiX / 96f;

            Text = "InstaPaste";
            Icon = Icon.FromHandle(Theme.Logo(32).GetHicon());
            AutoScaleMode = AutoScaleMode.None;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Theme.Bg;
            ForeColor = Theme.Text;
            DoubleBuffered = true;
            ClientSize = new Size(S(480), S(668));

            fBody = new Font("Segoe UI", 10.5f);
            fSmall = new Font("Segoe UI", 9f);
            fCaps = new Font("Segoe UI Semibold", 8f);
            fTitle = new Font("Segoe UI Semibold", 17f);

            AddLabel("InstaPaste", 78, 18, 300, 36, fTitle, Theme.Text, Theme.Bg);
            AddLabel("Screenshot, saved and copied. Just paste.", 80, 54, 340, 22, fSmall, Theme.Muted, Theme.Bg);

            // Shortcuts
            cards.Add(new Rectangle(24, 96, 432, 172));
            AddLabel("SHORTCUTS", 44, 112, 200, 18, fCaps, Theme.Muted, Theme.Card);
            AddLabel("Full screen", 44, 144, 220, 28, fBody, Theme.Text, Theme.Card);
            AddLabel("Pick an area", 44, 192, 220, 28, fBody, Theme.Text, Theme.Card);
            KeyBox full = new KeyBox(); full.Value = Settings.Full;
            full.Changed = delegate(Keys k) { Settings.Full = k; Settings.Store(); };
            Place(full, 276, 138, 160, 38);
            KeyBox area = new KeyBox(); area.Value = Settings.Area;
            area.Changed = delegate(Keys k) { Settings.Area = k; Settings.Store(); };
            Place(area, 276, 186, 160, 38);
            AddLabel("Click a box, then press any key you like.", 44, 234, 380, 20, fSmall, Theme.Muted, Theme.Card);

            // Folder
            cards.Add(new Rectangle(24, 284, 432, 100));
            AddLabel("SAVE SCREENSHOTS TO", 44, 300, 260, 18, fCaps, Theme.Muted, Theme.Card);
            pathLabel = AddLabel(Settings.Folder, 44, 330, 222, 28, fSmall, Theme.Text, Theme.Card);
            pathLabel.AutoEllipsis = true;
            FlatBtn change = new FlatBtn("Change", false);
            change.Click += delegate { PickFolder(); };
            Place(change, 276, 326, 76, 36);
            FlatBtn open = new FlatBtn("Open", false);
            open.Click += delegate { MainWindow.OpenFolder(); };
            Place(open, 360, 326, 76, 36);

            // Options
            cards.Add(new Rectangle(24, 400, 432, 196));
            AddToggle("Copy so I can paste it", 412, Settings.Copy, delegate(bool v) { Settings.Copy = v; Settings.Store(); });
            AddToggle("Save it to the folder", 456, Settings.Save, delegate(bool v) { Settings.Save = v; Settings.Store(); });
            AddToggle("Show a little popup", 500, Settings.Popup, delegate(bool v) { Settings.Popup = v; Settings.Store(); });
            AddToggle("Start with Windows", 544, Settings.StartupOn, delegate(bool v) { Settings.StartupOn = v; });

            // Footer
            AddLabel("Find InstaPaste near the clock, under Show hidden icons ( ^ ).", 26, 610, 240, 40, fSmall, Theme.Muted, Theme.Bg);
            FlatBtn quit = new FlatBtn("Quit", false);
            quit.Click += delegate { Application.Exit(); };
            Place(quit, 276, 612, 76, 38);
            FlatBtn done = new FlatBtn("Done", true);
            done.Click += delegate { Hide(); };
            Place(done, 360, 612, 96, 38);
        }

        Label AddLabel(string text, float x, float y, float w, float h, Font f, Color c, Color bg)
        {
            Label l = new Label();
            l.Text = text; l.Font = f; l.ForeColor = c; l.BackColor = bg;
            l.AutoSize = false; l.TextAlign = ContentAlignment.MiddleLeft;
            Place(l, x, y, w, h);
            return l;
        }

        void AddToggle(string text, float y, bool on, Action<bool> changed)
        {
            AddLabel(text, 44, y, 300, 32, fBody, Theme.Text, Theme.Card);
            Toggle t = new Toggle();
            t.Checked = on;
            t.Changed = changed;
            Place(t, 392, y + 5, 44, 24);
        }

        void Place(Control c, float x, float y, float w, float h)
        {
            c.Bounds = new Rectangle(S(x), S(y), S(w), S(h));
            if (!(c is Label)) c.BackColor = Theme.Card;
            if (c is FlatBtn && y > 600) c.BackColor = Theme.Bg;
            c.Font = c.Font == null || c is Label ? c.Font : fBody;
            Controls.Add(c);
        }

        void PickFolder()
        {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = "Where should InstaPaste save your screenshots?";
                d.SelectedPath = Settings.Folder;
                if (d.ShowDialog(this) == DialogResult.OK)
                {
                    Settings.Folder = d.SelectedPath;
                    Settings.Store();
                    pathLabel.Text = Settings.Folder;
                }
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try
            {
                int on = 1;
                DwmSetWindowAttribute(Handle, 20, ref on, 4);
                int round = 2;
                DwmSetWindowAttribute(Handle, 33, ref round, 4);
                int cap = Theme.Bg.R | (Theme.Bg.G << 8) | (Theme.Bg.B << 16);
                DwmSetWindowAttribute(Handle, 35, ref cap, 4);
                DwmSetWindowAttribute(Handle, 34, ref cap, 4);
            }
            catch { }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Bitmap logo = Theme.Logo(S(44)))
                g.DrawImage(logo, S(24), S(22));
            foreach (Rectangle r in cards)
            {
                RectangleF rf = new RectangleF(S(r.X), S(r.Y), S(r.Width), S(r.Height));
                using (GraphicsPath p = Theme.Round(rf, S(12)))
                using (Brush b = new SolidBrush(Theme.Card))
                using (Pen pen = new Pen(Theme.Line, 1f))
                {
                    g.FillPath(b, p);
                    g.DrawPath(pen, p);
                }
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
            if (KeyBox.Recorder != null) KeyBox.Recorder.Stop();
            base.OnFormClosing(e);
        }
    }

    public class KeyBox : Control
    {
        public static KeyBox Recorder;
        public Keys Value;
        public Action<Keys> Changed;
        bool hover;

        public KeyBox()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnClick(EventArgs e)
        {
            if (Recorder != null && Recorder != this) Recorder.Stop();
            Recorder = this;
            Invalidate();
            base.OnClick(e);
        }

        public void Stop() { Recorder = null; Invalidate(); }

        public void SetKey(Keys k)
        {
            Recorder = null;
            if ((k & Keys.KeyCode) != Keys.Escape)
            {
                Value = k;
                if (Changed != null) Changed(k);
            }
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            bool rec = Recorder == this;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            float rad = Height * 0.25f;
            Color fill = rec ? Color.FromArgb(50, Theme.Accent) : (hover ? Color.FromArgb(52, 52, 64) : Theme.Key);
            using (GraphicsPath p = Theme.Round(r, rad))
            using (Brush b = new SolidBrush(fill))
            using (Pen pen = new Pen(rec ? Theme.Accent : Theme.Line, rec ? 2f : 1f))
            {
                g.FillPath(b, p);
                g.DrawPath(pen, p);
            }
            string text = rec ? "Press a key..." : Theme.KeyName(Value);
            TextRenderer.DrawText(g, text, Font, new Rectangle(0, 0, Width, Height), rec ? Theme.AccentHover : Theme.Text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }

    public class Toggle : Control
    {
        public bool Checked;
        public Action<bool> Changed;

        public Toggle()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
        }

        protected override void OnClick(EventArgs e)
        {
            Checked = !Checked;
            Invalidate();
            if (Changed != null) Changed(Checked);
            base.OnClick(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (GraphicsPath p = Theme.Round(r, r.Height / 2))
            using (Brush b = new SolidBrush(Checked ? Theme.Accent : Theme.Key))
            using (Pen pen = new Pen(Checked ? Theme.Accent : Theme.Line))
            {
                g.FillPath(b, p);
                g.DrawPath(pen, p);
            }
            float pad = Height * 0.17f;
            float d = Height - pad * 2 - 1;
            float x = Checked ? Width - pad - d - 1 : pad;
            g.FillEllipse(Checked ? Brushes.White : new SolidBrush(Theme.Muted), x, pad, d, d);
        }
    }

    public class FlatBtn : Control
    {
        bool primary, hover;

        public FlatBtn(string text, bool isPrimary)
        {
            Text = text;
            primary = isPrimary;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = primary ? (hover ? Theme.AccentHover : Theme.Accent) : (hover ? Color.FromArgb(52, 52, 64) : Theme.Key);
            using (GraphicsPath p = Theme.Round(r, Height * 0.25f))
            using (Brush b = new SolidBrush(fill))
            {
                g.FillPath(b, p);
                if (!primary) using (Pen pen = new Pen(Theme.Line)) g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width, Height), Color.White,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    public class SelectForm : Form
    {
        Bitmap snap, dim;
        Point start;
        Rectangle sel = Rectangle.Empty;
        bool dragging;
        public Bitmap Result;

        public SelectForm(Bitmap snapshot, Rectangle bounds)
        {
            snap = snapshot;
            dim = new Bitmap(snap.Width, snap.Height, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(dim))
            {
                g.DrawImage(snap, 0, 0, snap.Width, snap.Height);
                using (Brush b = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
                    g.FillRectangle(b, 0, 0, snap.Width, snap.Height);
            }

            AutoScaleMode = AutoScaleMode.None;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            TopMost = true;
            DoubleBuffered = true;
            KeyPreview = true;
            Cursor = Cursors.Cross;
            Bounds = bounds;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            Activate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape) Close();
            base.OnKeyDown(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right) { Close(); return; }
            if (e.Button == MouseButtons.Left) { dragging = true; start = e.Location; sel = Rectangle.Empty; }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (!dragging) return;
            Rectangle old = sel;
            sel = Rectangle.FromLTRB(Math.Min(start.X, e.X), Math.Min(start.Y, e.Y), Math.Max(start.X, e.X), Math.Max(start.Y, e.Y));
            Rectangle area = Rectangle.Union(old, sel);
            area.Inflate(6, 40);
            Invalidate(area);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (!dragging || e.Button != MouseButtons.Left) return;
            dragging = false;
            if (sel.Width > 3 && sel.Height > 3)
            {
                Result = new Bitmap(sel.Width, sel.Height, PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(Result))
                    g.DrawImage(snap, new Rectangle(0, 0, sel.Width, sel.Height), sel, GraphicsUnit.Pixel);
            }
            Close();
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.DrawImage(dim, e.ClipRectangle, e.ClipRectangle, GraphicsUnit.Pixel);
            if (sel.Width > 0 && sel.Height > 0)
            {
                g.DrawImage(snap, sel, sel, GraphicsUnit.Pixel);
                using (Pen p = new Pen(Theme.Accent, 2))
                    g.DrawRectangle(p, sel);
                string label = sel.Width + " x " + sel.Height;
                using (Font f = new Font("Segoe UI", 9f))
                {
                    Size ts = TextRenderer.MeasureText(label, f);
                    int y = sel.Y > ts.Height + 10 ? sel.Y - ts.Height - 6 : sel.Bottom + 6;
                    Rectangle box = new Rectangle(sel.X, y, ts.Width + 8, ts.Height + 2);
                    g.FillRectangle(new SolidBrush(Theme.Accent), box);
                    TextRenderer.DrawText(g, label, f, box, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                }
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && dim != null) { dim.Dispose(); dim = null; }
            base.Dispose(disposing);
        }
    }

    public class Toast : Form
    {
        const int WS_EX_TOPMOST = 0x8, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
        static Toast current;
        string text;
        float scale = 1f;

        public static void Show(string message)
        {
            if (current != null && !current.IsDisposed) current.Close();
            current = new Toast(message);
            current.Show();
        }

        Toast(string message)
        {
            text = message;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = Theme.Card;

            Screen s = Screen.FromPoint(Cursor.Position);
            using (Graphics g = CreateGraphics()) scale = g.DpiX / 96f;
            Font = new Font("Segoe UI", 10f);
            Size measured = TextRenderer.MeasureText(text, Font);
            Size = new Size(measured.Width + (int)(52 * scale), measured.Height + (int)(24 * scale));
            Location = new Point(s.WorkingArea.Right - Width - (int)(20 * scale), s.WorkingArea.Bottom - Height - (int)(20 * scale));
            using (GraphicsPath p = Theme.Round(new RectangleF(0, 0, Width, Height), 10 * scale))
                Region = new Region(p);

            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 1600;
            t.Tick += delegate { t.Stop(); t.Dispose(); Close(); };
            t.Start();
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
                return cp;
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int logo = (int)(18 * scale);
            using (Bitmap b = Theme.Logo(logo))
                g.DrawImage(b, (int)(14 * scale), (Height - logo) / 2);
            TextRenderer.DrawText(g, text, Font, new Rectangle((int)(40 * scale), 0, Width - (int)(40 * scale), Height), Theme.Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }
    }
}
'@

[InstaPaste.App]::Run($PSCommandPath)
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("InstaPaste could not start:`n`n" + $_.Exception.Message, "InstaPaste") | Out-Null
}
