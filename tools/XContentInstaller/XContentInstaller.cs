// Install DLC / squad saves from your own Xbox 360 into the 2010 FIFA World Cup PC port.
//
// Windows-only GUI (WinForms, .NET Framework 4.x, C# 5 so it builds with the csc.exe that ships
// with Windows). Same logic as tools/install_xcontent.py: extracts STFS packages (CON / LIVE /
// PIRS) into the layout the ReXGlue runtime reads:
//
//   <root>\<XUID>\454108E4\<type>\<package>\<files>
//   <root>\<XUID>\454108E4\Headers\<type>\<package>.header
//
// No game content is included. Users supply packages from their own console.
//
// Usage:
//   InstallDLC.exe                         open the window
//   InstallDLC.exe <folder>                open the window with <folder> selected
//   InstallDLC.exe --install <path> [--root <dir>]
//                                          install without a window; prints a report and
//                                          returns 0 on success (for scripts / the launcher)

using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("2010 FIFA World Cup - Install DLC")]
[assembly: System.Reflection.AssemblyProduct("2010 FIFA World Cup PC Port")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace Fwc10.XContent
{
    internal sealed class StfsEntry
    {
        public string Name;
        public bool IsDirectory;
        public int AllocatedBlocks;
        public int StartBlock;
        public int Parent;
        public long Length;
    }

    /// <summary>Read-only STFS reader. Mirrors rex::filesystem::StfsContainerDevice.</summary>
    internal sealed class StfsPackage : IDisposable
    {
        private const int Block = 0x1000;
        private const int L0 = 170;
        private const int L1 = 170 * 170;
        private const int EndOfChain = 0xFFFFFF;

        private readonly FileStream _file;
        private readonly Dictionary<long, byte[]> _tables = new Dictionary<long, byte[]>();
        private readonly int _blocksPerHashTable;
        private readonly int _step0;
        private readonly int _step1;
        private readonly long _base;
        private readonly bool _readOnly;
        private readonly bool _rootActive;
        private readonly int _fileTableCount;
        private readonly int _fileTableBlock;
        private readonly long _totalBlocks;

        public readonly string Path;
        public readonly string Magic;
        public readonly uint ContentType;
        public readonly uint TitleId;
        public readonly string DisplayName;

        public StfsPackage(string path)
        {
            Path = path;
            _file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            byte[] h = new byte[0x971A];
            int read = ReadFully(_file, 0, h, h.Length);
            if (read < 0x1700) throw new InvalidDataException("file too small to be a package");
            Magic = Encoding.ASCII.GetString(h, 0, 4);
            if (Magic != "CON " && Magic != "LIVE" && Magic != "PIRS")
                throw new InvalidDataException("not an Xbox 360 package");
            uint headerSize = BE32(h, 0x340);
            ContentType = BE32(h, 0x344);
            TitleId = BE32(h, 0x360);
            if (BE32(h, 0x3A9) != 0) throw new InvalidDataException("SVOD packages are not supported");
            byte flags = h[0x37B];
            _readOnly = (flags & 1) != 0;
            _rootActive = (flags & 2) != 0;
            _fileTableCount = h[0x37C] | (h[0x37D] << 8);
            _fileTableBlock = LE24(h, 0x37E);
            _totalBlocks = BE32(h, 0x395);
            DisplayName = Utf16BE(h, 0x411, 0x100);
            _blocksPerHashTable = _readOnly ? 1 : 2;
            _step0 = L0 + _blocksPerHashTable;
            _step1 = L1 + (L0 + 1) * _blocksPerHashTable;
            _base = (headerSize + Block - 1) & ~(long)(Block - 1);
        }

        public bool IsDlc { get { return ContentType == 2; } }
        public bool IsSave { get { return ContentType == 1; } }

        public void Dispose() { _file.Dispose(); }

        private long BlockOffset(long index)
        {
            long b = L0, block = index;
            for (int i = 0; i < 3; i++)
            {
                block += ((index + b) / b) * _blocksPerHashTable;
                if (index < b) break;
                b *= L0;
            }
            return _base + (block << 12);
        }

        private long HashBlockNumber(long index, int level)
        {
            if (level == 0)
            {
                if (index < L0) return 0;
                long b = (index / L0) * _step0 + ((index / L1) + 1) * _blocksPerHashTable;
                return index < L1 ? b : b + _blocksPerHashTable;
            }
            if (level == 1)
            {
                if (index < L1) return _step0;
                return (index / L1) * _step1 + _blocksPerHashTable;
            }
            return _step1;
        }

        private byte[] Table(long offset)
        {
            byte[] t;
            if (!_tables.TryGetValue(offset, out t))
            {
                t = new byte[Block];
                ReadFully(_file, offset, t, Block);
                _tables[offset] = t;
            }
            return t;
        }

        private static uint Info(byte[] table, long record)
        {
            return BE32(table, (int)(record * 0x18 + 0x14));
        }

        private int NextBlock(long index)
        {
            long secondary = _rootActive ? Block : 0;
            long off0 = _base + (HashBlockNumber(index, 0) << 12);
            if (_readOnly)
            {
                secondary = 0;
            }
            else if (_totalBlocks > L0)
            {
                long off1 = _base + (HashBlockNumber(index, 1) << 12);
                if (_totalBlocks > L1)
                {
                    long off2 = _base + (HashBlockNumber(index, 2) << 12);
                    uint i2 = Info(Table(off2 + secondary), (index / L1) % L0);
                    secondary = (i2 & 0x40000000) != 0 ? Block : 0;
                }
                uint i1 = Info(Table(off1 + secondary), (index / L0) % L0);
                secondary = (i1 & 0x40000000) != 0 ? Block : 0;
            }
            return (int)(Info(Table(off0 + secondary), index % L0) & 0xFFFFFF);
        }

        public List<StfsEntry> Entries()
        {
            List<StfsEntry> list = new List<StfsEntry>();
            int block = _fileTableBlock;
            byte[] d = new byte[Block];
            for (int n = 0; n < _fileTableCount; n++)
            {
                ReadFully(_file, BlockOffset(block), d, Block);
                for (int m = 0; m < Block / 0x40; m++)
                {
                    int o = m * 0x40;
                    if (d[o] == 0) break;
                    byte fl = d[o + 0x28];
                    StfsEntry e = new StfsEntry();
                    e.Name = Encoding.GetEncoding(28591).GetString(d, o, fl & 0x3F);
                    e.IsDirectory = (fl & 0x80) != 0;
                    e.AllocatedBlocks = LE24(d, o + 0x2C);
                    e.StartBlock = LE24(d, o + 0x2F);
                    e.Parent = (d[o + 0x32] << 8) | d[o + 0x33];
                    e.Length = BE32(d, o + 0x34);
                    list.Add(e);
                }
                block = NextBlock(block);
                if (block == EndOfChain) break;
            }
            return list;
        }

        public string RelativePath(List<StfsEntry> entries, int index)
        {
            List<string> parts = new List<string>();
            int i = index;
            int guard = 0;
            while (i != 0xFFFF)
            {
                if (i < 0 || i >= entries.Count || ++guard > 64)
                    throw new InvalidDataException("bad directory tree");
                parts.Insert(0, entries[i].Name);
                i = entries[i].Parent;
            }
            return string.Join("\\", parts.ToArray());
        }

        public byte[] ReadFile(StfsEntry e)
        {
            byte[] data = new byte[e.Length];
            long pos = 0, remaining = e.Length;
            int idx = e.StartBlock, blocks = 0;
            while (remaining > 0 && idx != EndOfChain)
            {
                int n = (int)Math.Min(Block, remaining);
                ReadFully(_file, BlockOffset(idx), data, n, pos);
                pos += n;
                remaining -= n;
                blocks++;
                idx = NextBlock(idx);
            }
            if (remaining != 0 || blocks != e.AllocatedBlocks)
                throw new InvalidDataException(string.Format(
                    "bad block chain for {0}: {1} bytes missing, {2}/{3} blocks",
                    e.Name, remaining, blocks, e.AllocatedBlocks));
            return data;
        }

        // ---- helpers ----
        internal static uint BE32(byte[] b, int o)
        {
            return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3];
        }

        private static int LE24(byte[] b, int o) { return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16); }

        private static string Utf16BE(byte[] b, int o, int max)
        {
            int len = 0;
            while (len + 1 < max && (b[o + len] != 0 || b[o + len + 1] != 0)) len += 2;
            return Encoding.BigEndianUnicode.GetString(b, o, len);
        }

        private static int ReadFully(FileStream f, long offset, byte[] buf, int count, long bufOffset = 0)
        {
            f.Seek(offset, SeekOrigin.Begin);
            int total = 0;
            while (total < count)
            {
                int r = f.Read(buf, (int)bufOffset + total, count - total);
                if (r <= 0) break;
                total += r;
            }
            return total;
        }
    }

    internal static class Installer
    {
        public const uint GameTitleId = 0x454108E4;
        public const ulong SharedXuid = 0;
        public const ulong DefaultProfileXuid = 0xB13EBABEBABEBABE;

        public static string DefaultRoot
        {
            get
            {
                return System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                    "FIFA World Cup 2010");
            }
        }

        public static List<string> FindPackages(string path)
        {
            List<string> found = new List<string>();
            if (File.Exists(path))
            {
                if (HasPackageMagic(path)) found.Add(path);
                return found;
            }
            if (!Directory.Exists(path)) return found;
            List<string> files = new List<string>(Directory.GetFiles(path, "*", SearchOption.AllDirectories));
            files.Sort(StringComparer.OrdinalIgnoreCase);
            foreach (string f in files)
                if (HasPackageMagic(f)) found.Add(f);
            return found;
        }

        private static bool HasPackageMagic(string path)
        {
            try
            {
                using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    byte[] m = new byte[4];
                    if (fs.Read(m, 0, 4) != 4) return false;
                    string s = Encoding.ASCII.GetString(m);
                    return s == "CON " || s == "LIVE" || s == "PIRS";
                }
            }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
        }

        /// <summary>Why a package cannot be installed, or null if it can.</summary>
        public static string Rejection(StfsPackage p)
        {
            if (p.TitleId != 0 && p.TitleId != GameTitleId)
                return string.Format("for another game ({0:X8})", p.TitleId);
            if (!p.IsDlc && !p.IsSave)
                return string.Format("unsupported content type {0:X8}", p.ContentType);
            return null;
        }

        public static ulong XuidFor(StfsPackage p, ulong profileXuid)
        {
            return p.IsDlc ? SharedXuid : profileXuid;
        }

        public static string PackageFolder(string root, StfsPackage p, ulong profileXuid)
        {
            return System.IO.Path.Combine(root, string.Format("{0:X16}", XuidFor(p, profileXuid)),
                string.Format("{0:X8}", GameTitleId), string.Format("{0:X8}", p.ContentType),
                System.IO.Path.GetFileName(p.Path));
        }

        public static string HeaderFile(string root, StfsPackage p, ulong profileXuid)
        {
            return System.IO.Path.Combine(root, string.Format("{0:X16}", XuidFor(p, profileXuid)),
                string.Format("{0:X8}", GameTitleId), "Headers", string.Format("{0:X8}", p.ContentType),
                System.IO.Path.GetFileName(p.Path) + ".header");
        }

        public static bool IsInstalled(string root, StfsPackage p, ulong profileXuid)
        {
            return Directory.Exists(PackageFolder(root, p, profileXuid))
                && File.Exists(HeaderFile(root, p, profileXuid));
        }

        /// <summary>Extracts the package. Every file is read and checked before anything is written.</summary>
        public static int Install(string root, StfsPackage p, ulong profileXuid)
        {
            List<StfsEntry> entries = p.Entries();
            List<KeyValuePair<string, byte[]>> files = new List<KeyValuePair<string, byte[]>>();
            for (int i = 0; i < entries.Count; i++)
            {
                if (entries[i].IsDirectory) continue;
                string rel = p.RelativePath(entries, i);
                if (rel.Contains("..") || System.IO.Path.IsPathRooted(rel))
                    throw new InvalidDataException("unsafe path in package: " + rel);
                files.Add(new KeyValuePair<string, byte[]>(rel, p.ReadFile(entries[i])));
            }

            string dest = PackageFolder(root, p, profileXuid);
            foreach (KeyValuePair<string, byte[]> f in files)
            {
                string outPath = System.IO.Path.Combine(dest, f.Key);
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(outPath));
                File.WriteAllBytes(outPath, f.Value);
            }

            string header = HeaderFile(root, p, profileXuid);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(header));
            File.WriteAllBytes(header, BuildHeader(p, profileXuid));
            return files.Count;
        }

        /// <summary>XCONTENT_AGGREGATE_DATA (0x148 bytes) + BE license mask FFFFFFFF for DLC.</summary>
        private static byte[] BuildHeader(StfsPackage p, ulong profileXuid)
        {
            byte[] b = new byte[p.IsDlc ? 0x14C : 0x148];
            PutBE32(b, 0, 1);                       // device_id = HDD
            PutBE32(b, 4, p.ContentType);
            string name = string.IsNullOrEmpty(p.DisplayName) ? System.IO.Path.GetFileName(p.Path) : p.DisplayName;
            byte[] dn = Encoding.BigEndianUnicode.GetBytes(name);
            Array.Copy(dn, 0, b, 8, Math.Min(dn.Length, 0xFE));
            // file_name is char[42]; 42-character DLC names fill it completely (unterminated).
            byte[] fn = Encoding.GetEncoding(28591).GetBytes(System.IO.Path.GetFileName(p.Path));
            Array.Copy(fn, 0, b, 0x108, Math.Min(fn.Length, 42));
            ulong xuid = XuidFor(p, profileXuid);
            PutBE32(b, 0x138, (uint)(xuid >> 32));
            PutBE32(b, 0x13C, (uint)xuid);
            PutBE32(b, 0x140, GameTitleId);
            if (p.IsDlc) PutBE32(b, 0x148, 0xFFFFFFFF);
            return b;
        }

        private static void PutBE32(byte[] b, int o, uint v)
        {
            b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v;
        }

        public static string KindLabel(StfsPackage p)
        {
            if (p.IsDlc) return "DLC";
            if (p.IsSave)
                return System.IO.Path.GetFileName(p.Path).StartsWith("Squads", StringComparison.OrdinalIgnoreCase)
                    ? "Squads (save)" : "Save";
            return string.Format("{0:X8}", p.ContentType);
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly TextBox _source = new TextBox();
        private readonly TextBox _root = new TextBox();
        private readonly ListView _list = new ListView();
        private readonly Button _install = new Button();
        private readonly Label _status = new Label();
        private readonly List<string> _paths = new List<string>();

        private static readonly Color Green = Color.FromArgb(0, 139, 105);
        private static readonly Color Dark = Color.FromArgb(24, 32, 30);

        public MainForm(string initialSource)
        {
            Text = "Install DLC & Squads - 2010 FIFA World Cup";
            Font = new Font("Segoe UI", 9f);
            ClientSize = new Size(760, 500);
            MinimumSize = new Size(640, 420);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(237, 240, 237);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            Panel header = new Panel();
            header.Dock = DockStyle.Top;
            header.Height = 64;
            header.BackColor = Dark;
            Label title = new Label();
            title.Text = "INSTALL DLC & SQUADS";
            title.UseMnemonic = false;
            title.Font = new Font("Segoe UI", 16f, FontStyle.Bold);
            title.ForeColor = Color.White;
            title.AutoSize = true;
            title.Location = new Point(16, 8);
            Label subtitle = new Label();
            subtitle.Text = "Kits, balls, adboards and squad files copied from your own Xbox 360";
            subtitle.ForeColor = Color.FromArgb(245, 221, 157);
            subtitle.AutoSize = true;
            subtitle.Location = new Point(19, 40);
            header.Controls.Add(title);
            header.Controls.Add(subtitle);

            Label srcLabel = MakeLabel("1. Folder with your packages", 76);
            _source.SetBounds(16, 96, 610, 24);
            _source.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            Button srcBrowse = MakeButton("Browse...", 634, 95);
            srcBrowse.Click += delegate { BrowseSource(); };

            Label rootLabel = MakeLabel("2. Game save folder (leave as is unless you moved it)", 128);
            _root.SetBounds(16, 148, 610, 24);
            _root.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            _root.Text = Installer.DefaultRoot;
            Button rootBrowse = MakeButton("Browse...", 634, 147);
            rootBrowse.Click += delegate { BrowseRoot(); };

            _list.SetBounds(16, 184, 728, 248);
            _list.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            _list.View = View.Details;
            _list.CheckBoxes = true;
            _list.FullRowSelect = true;
            _list.HideSelection = false;
            _list.Columns.Add("Content", 300);
            _list.Columns.Add("Type", 110);
            _list.Columns.Add("Size", 80, HorizontalAlignment.Right);
            _list.Columns.Add("Status", 220);

            _status.SetBounds(16, 444, 560, 40);
            _status.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            _status.Text = "Choose the folder where you copied the DLC / squad files from your console.";

            _install.Text = "Install selected";
            _install.SetBounds(594, 446, 150, 34);
            _install.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            _install.FlatStyle = FlatStyle.Flat;
            _install.BackColor = Green;
            _install.ForeColor = Color.White;
            _install.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
            _install.Enabled = false;
            _install.Click += delegate { InstallChecked(); };

            Controls.AddRange(new Control[] {
                header, srcLabel, _source, srcBrowse, rootLabel, _root, rootBrowse, _list, _status, _install });

            _source.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) Scan(); };
            _root.Leave += delegate { if (_paths.Count > 0) Scan(); };

            if (!string.IsNullOrEmpty(initialSource))
            {
                _source.Text = initialSource;
                Shown += delegate { Scan(); };
            }
        }

        private Label MakeLabel(string text, int top)
        {
            Label l = new Label();
            l.Text = text;
            l.AutoSize = true;
            l.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
            l.Location = new Point(14, top);
            return l;
        }

        private Button MakeButton(string text, int left, int top)
        {
            Button b = new Button();
            b.Text = text;
            b.SetBounds(left, top, 110, 26);
            b.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            b.FlatStyle = FlatStyle.Flat;
            b.BackColor = Green;
            b.ForeColor = Color.White;
            return b;
        }

        private void BrowseSource()
        {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = "Select the folder with the files copied from your Xbox 360 " +
                                "(for example the 454108E4 folder).";
                if (Directory.Exists(_source.Text)) d.SelectedPath = _source.Text;
                if (d.ShowDialog(this) == DialogResult.OK)
                {
                    _source.Text = d.SelectedPath;
                    Scan();
                }
            }
        }

        private void BrowseRoot()
        {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = "Select the game's save folder (normally Documents\\FIFA World Cup 2010).";
                if (Directory.Exists(_root.Text)) d.SelectedPath = _root.Text;
                if (d.ShowDialog(this) == DialogResult.OK)
                {
                    _root.Text = d.SelectedPath;
                    if (_paths.Count > 0) Scan();
                }
            }
        }

        private void Scan()
        {
            _list.Items.Clear();
            _paths.Clear();
            string src = _source.Text.Trim().Trim('"');
            if (src.Length == 0) return;
            Cursor = Cursors.WaitCursor;
            try
            {
                List<string> found = Installer.FindPackages(src);
                int ready = 0;
                foreach (string path in found)
                {
                    ListViewItem item;
                    try
                    {
                        using (StfsPackage p = new StfsPackage(path))
                        {
                            string name = string.IsNullOrEmpty(p.DisplayName) ? Path.GetFileName(path) : p.DisplayName;
                            item = new ListViewItem(name);
                            item.SubItems.Add(Installer.KindLabel(p));
                            item.SubItems.Add(FormatSize(new FileInfo(path).Length));
                            string reject = Installer.Rejection(p);
                            if (reject != null)
                            {
                                item.SubItems.Add("Skipped: " + reject);
                                item.ForeColor = Color.Gray;
                            }
                            else if (Installer.IsInstalled(_root.Text, p, Installer.DefaultProfileXuid))
                            {
                                item.SubItems.Add("Already installed (tick to reinstall)");
                                item.Checked = false;
                            }
                            else
                            {
                                item.SubItems.Add("Ready");
                                item.Checked = true;
                                ready++;
                            }
                            item.Tag = reject == null ? path : null;
                        }
                    }
                    catch (Exception ex)
                    {
                        item = new ListViewItem(Path.GetFileName(path));
                        item.SubItems.Add("?");
                        item.SubItems.Add(FormatSize(new FileInfo(path).Length));
                        item.SubItems.Add("Unreadable: " + ex.Message);
                        item.ForeColor = Color.Firebrick;
                    }
                    item.ToolTipText = path;
                    _list.Items.Add(item);
                    _paths.Add(path);
                }
                _list.ShowItemToolTips = true;
                _install.Enabled = _list.Items.Count > 0;
                if (found.Count == 0)
                    _status.Text = "No Xbox 360 packages were found in that folder.";
                else
                    _status.Text = string.Format("Found {0} package(s), {1} new. Tick what you want and press Install.",
                        found.Count, ready);
            }
            catch (Exception ex)
            {
                _status.Text = "Could not read the folder: " + ex.Message;
            }
            finally
            {
                Cursor = Cursors.Default;
            }
        }

        private void InstallChecked()
        {
            string root = _root.Text.Trim().Trim('"');
            if (root.Length == 0) { _status.Text = "Choose the game save folder first."; return; }
            int ok = 0, failed = 0, dlc = 0, squads = 0;
            Cursor = Cursors.WaitCursor;
            _install.Enabled = false;
            try
            {
                foreach (ListViewItem item in _list.Items)
                {
                    string path = item.Tag as string;
                    if (!item.Checked || path == null) continue;
                    try
                    {
                        using (StfsPackage p = new StfsPackage(path))
                        {
                            int n = Installer.Install(root, p, Installer.DefaultProfileXuid);
                            item.SubItems[3].Text = string.Format("Installed ({0} files)", n);
                            item.ForeColor = Green;
                            item.Checked = false;
                            ok++;
                            if (p.IsDlc) dlc++;
                            else if (Installer.KindLabel(p).StartsWith("Squads")) squads++;
                        }
                    }
                    catch (Exception ex)
                    {
                        item.SubItems[3].Text = "Error: " + ex.Message;
                        item.ForeColor = Color.Firebrick;
                        failed++;
                    }
                    Application.DoEvents();
                }
            }
            finally
            {
                Cursor = Cursors.Default;
                _install.Enabled = true;
            }

            StringBuilder msg = new StringBuilder();
            msg.AppendFormat("Installed {0} package(s)", ok);
            if (failed > 0) msg.AppendFormat(", {0} failed", failed);
            msg.Append(". ");
            if (dlc > 0) msg.Append("DLC loads automatically when the game starts. ");
            if (squads > 0) msg.Append("Load the squads from the game's squad menu.");
            _status.Text = msg.ToString();
        }

        private static string FormatSize(long bytes)
        {
            if (bytes >= 1024 * 1024) return string.Format("{0:0.0} MB", bytes / (1024.0 * 1024.0));
            return string.Format("{0:0} KB", Math.Ceiling(bytes / 1024.0));
        }
    }

    internal static class Program
    {
        [DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int processId);

        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--install")
                return RunSilent(args);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm(args.Length > 0 ? args[0] : null));
            return 0;
        }

        private static int RunSilent(string[] args)
        {
            AttachConsole(-1);
            string root = Installer.DefaultRoot;
            List<string> inputs = new List<string>();
            for (int i = 1; i < args.Length; i++)
            {
                if (args[i] == "--root" && i + 1 < args.Length) root = args[++i];
                else inputs.Add(args[i]);
            }
            Console.WriteLine();
            if (inputs.Count == 0)
            {
                Console.WriteLine("usage: InstallDLC.exe --install <file or folder>... [--root <dir>]");
                return 2;
            }
            int ok = 0, failed = 0;
            foreach (string input in inputs)
            {
                foreach (string path in Installer.FindPackages(input))
                {
                    try
                    {
                        using (StfsPackage p = new StfsPackage(path))
                        {
                            string reject = Installer.Rejection(p);
                            if (reject != null)
                            {
                                Console.WriteLine("SKIP  {0}: {1}", Path.GetFileName(path), reject);
                                continue;
                            }
                            int n = Installer.Install(root, p, Installer.DefaultProfileXuid);
                            Console.WriteLine("OK    {0} [{1}] {2} files -> {3}", Path.GetFileName(path),
                                Installer.KindLabel(p), n, Installer.PackageFolder(root, p, Installer.DefaultProfileXuid));
                            ok++;
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine("FAIL  {0}: {1}", Path.GetFileName(path), ex.Message);
                        failed++;
                    }
                }
            }
            Console.WriteLine("{0} installed, {1} failed", ok, failed);
            return failed > 0 ? 1 : (ok > 0 ? 0 : 3);
        }
    }
}
