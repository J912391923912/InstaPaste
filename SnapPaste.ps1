# SnapPaste: Ctrl+Shift+1 = full screen, Ctrl+Shift+2 = area. Saves to Pictures\SnapPaste and copies to clipboard.

$ErrorActionPreference = 'Stop'

try {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SnapPaste
{
    public static class App
    {
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        public static string Folder;
        public static string ScriptPath;

        public static void Run(string scriptPath)
        {
            try { if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) SetProcessDPIAware(); }
            catch { try { SetProcessDPIAware(); } catch { } }

            bool created;
            Mutex mutex = new Mutex(true, "SnapPaste_SingleInstance", out created);
            if (!created)
            {
                MessageBox.Show("SnapPaste is already running. Look for the purple icon near the clock.", "SnapPaste");
                return;
            }

            ScriptPath = scriptPath;
            Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "SnapPaste");
            Directory.CreateDirectory(Folder);

            Application.EnableVisualStyles();
            Application.Run(new MainWindow());
            GC.KeepAlive(mutex);
        }

        public static void Deliver(Bitmap bmp)
        {
            string name = "SnapPaste_" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss-fff") + ".png";
            string path = Path.Combine(Folder, name);
            bmp.Save(path, ImageFormat.Png);

            DataObject data = new DataObject();
            data.SetImage(bmp);
            MemoryStream png = new MemoryStream();
            bmp.Save(png, ImageFormat.Png);
            data.SetData("PNG", false, png);
            try { Clipboard.SetDataObject(data, true, 10, 100); } catch { }

            Toast.Show("Copied! Paste with Ctrl+V");
        }
    }

    public class MainWindow : Form
    {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        const int WM_HOTKEY = 0x0312;
        const uint MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_NOREPEAT = 0x4000;
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        NotifyIcon tray;
        bool busy;

        public MainWindow()
        {
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.None;
            Opacity = 0;

            tray = new NotifyIcon();
            tray.Icon = MakeIcon();
            tray.Text = "SnapPaste  (Ctrl+Shift+1 / Ctrl+Shift+2)";
            tray.Visible = true;
            tray.DoubleClick += delegate { OpenFolder(); };

            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add("Full screen   (Ctrl+Shift+1)", null, delegate { CaptureFull(); });
            menu.Items.Add("Pick area   (Ctrl+Shift+2)", null, delegate { CaptureArea(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Open screenshots folder", null, delegate { OpenFolder(); });
            ToolStripMenuItem startup = new ToolStripMenuItem("Start with Windows");
            startup.Checked = IsStartupOn();
            startup.Click += delegate { SetStartup(!startup.Checked); startup.Checked = IsStartupOn(); };
            menu.Items.Add(startup);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit", null, delegate { Close(); });
            tray.ContextMenuStrip = menu;
        }

        protected override void SetVisibleCore(bool value)
        {
            if (!IsHandleCreated) CreateHandle();
            base.SetVisibleCore(false);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            bool a = RegisterHotKey(Handle, 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, (uint)Keys.D1);
            bool b = RegisterHotKey(Handle, 2, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, (uint)Keys.D2);
            if (!a || !b)
                MessageBox.Show("Another app is already using Ctrl+Shift+1 or Ctrl+Shift+2. You can still use the tray icon menu.", "SnapPaste");
            else
                Toast.Show("SnapPaste is ready!  Ctrl+Shift+1 full  |  Ctrl+Shift+2 area");
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                int id = m.WParam.ToInt32();
                if (id == 1) CaptureFull();
                if (id == 2) CaptureArea();
            }
            base.WndProc(ref m);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            UnregisterHotKey(Handle, 1);
            UnregisterHotKey(Handle, 2);
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
            catch (Exception ex) { MessageBox.Show(ex.Message, "SnapPaste"); }
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
            catch (Exception ex) { MessageBox.Show(ex.Message, "SnapPaste"); }
            finally { busy = false; }
        }

        static Bitmap Grab(Rectangle r)
        {
            Bitmap bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
                g.CopyFromScreen(r.X, r.Y, 0, 0, r.Size, CopyPixelOperation.SourceCopy);
            return bmp;
        }

        static void OpenFolder()
        {
            System.Diagnostics.Process.Start("explorer.exe", "\"" + App.Folder + "\"");
        }

        static bool IsStartupOn()
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey))
                return k != null && k.GetValue("SnapPaste") != null;
        }

        static void SetStartup(bool on)
        {
            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (on)
                    k.SetValue("SnapPaste", "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + App.ScriptPath + "\"");
                else
                    k.DeleteValue("SnapPaste", false);
            }
        }

        static Icon MakeIcon()
        {
            Bitmap bmp = new Bitmap(32, 32);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (GraphicsPath p = Rounded(new Rectangle(1, 1, 30, 30), 8))
                using (Brush bg = new SolidBrush(Color.FromArgb(124, 92, 255)))
                    g.FillPath(bg, p);
                using (Pen w = new Pen(Color.White, 3))
                {
                    g.DrawLines(w, new Point[] { new Point(8, 14), new Point(8, 8), new Point(14, 8) });
                    g.DrawLines(w, new Point[] { new Point(18, 24), new Point(24, 24), new Point(24, 18) });
                }
                g.FillEllipse(Brushes.White, 13, 13, 6, 6);
            }
            return Icon.FromHandle(bmp.GetHicon());
        }

        public static GraphicsPath Rounded(Rectangle r, int radius)
        {
            int d = radius * 2;
            GraphicsPath p = new GraphicsPath();
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
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
            area.Inflate(4, 30);
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
                using (Pen p = new Pen(Color.FromArgb(124, 92, 255), 2))
                    g.DrawRectangle(p, sel);
                string label = sel.Width + " x " + sel.Height;
                using (Font f = new Font("Segoe UI", 9f))
                {
                    int y = sel.Y > 24 ? sel.Y - 22 : sel.Bottom + 4;
                    g.FillRectangle(Brushes.Black, sel.X, y, TextRenderer.MeasureText(label, f).Width, 18);
                    g.DrawString(label, f, Brushes.White, sel.X + 2, y + 1);
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
            BackColor = Color.FromArgb(28, 28, 32);

            Screen s = Screen.FromPoint(Cursor.Position);
            float scale;
            using (Graphics g = CreateGraphics()) scale = g.DpiX / 96f;
            Font = new Font("Segoe UI", 10f);
            Size measured = TextRenderer.MeasureText(text, Font);
            Size = new Size(measured.Width + (int)(36 * scale), measured.Height + (int)(22 * scale));
            Location = new Point(s.WorkingArea.Right - Width - (int)(20 * scale), s.WorkingArea.Bottom - Height - (int)(20 * scale));
            using (GraphicsPath p = MainWindow.Rounded(new Rectangle(0, 0, Width, Height), (int)(8 * scale)))
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
            e.Graphics.FillEllipse(new SolidBrush(Color.FromArgb(124, 92, 255)), 12, Height / 2 - 4, 8, 8);
            TextRenderer.DrawText(e.Graphics, text, Font, new Rectangle(14, 0, Width - 14, Height), Color.White,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }
}
'@

[SnapPaste.App]::Run($PSCommandPath)
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("SnapPaste could not start:`n`n" + $_.Exception.Message, "SnapPaste") | Out-Null
}
