// stream_viewer.cs - shows the camera video the board sends over Ethernet (UDP).
//
// Packet format (little endian), one packet per image line:
//     u32 frame number | u16 line (0..479) | u16 payload bytes (1280) | 640 pixels RGB565
// The viewer first sends a short "hello" packet to the board (port 5000); the board then
// streams frames back to whoever said hello, and stops a few seconds after the hellos stop.
//
// Build (no extra tools needed, the .NET compiler ships with Windows):
//   pc\build.bat
// Run:
//   pc\stream_viewer.exe [board IP]        (default 192.168.1.10)
//   pc\stream_viewer.exe --selftest        (checks the packet handling without the board)
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

static class P
{
    public const int W = 640, H = 480, LineBytes = W * 2, Hdr = 8, Port = 5000;
}

// Collects line packets into a frame; reports when the last line of a frame arrives.
class FrameAssembler
{
    public readonly byte[] Buf = new byte[P.W * P.H * 2];
    uint cur = uint.MaxValue;
    int got;
    public int LinesLost, FramesDone, BadPackets;

    public bool Add(byte[] pkt, int len)
    {
        if (len != P.Hdr + P.LineBytes) { BadPackets++; return false; }
        uint frame = BitConverter.ToUInt32(pkt, 0);
        int line = BitConverter.ToUInt16(pkt, 4);
        int n = BitConverter.ToUInt16(pkt, 6);
        if (n != P.LineBytes || line >= P.H) { BadPackets++; return false; }
        if (frame != cur)
        {
            if (cur != uint.MaxValue && got < P.H) LinesLost += P.H - got;   // previous frame was incomplete
            cur = frame; got = 0;
        }
        Buffer.BlockCopy(pkt, P.Hdr, Buf, line * P.LineBytes, P.LineBytes);
        got++;
        if (line != P.H - 1) return false;
        if (got < P.H) LinesLost += P.H - got;
        got = P.H;                       // already counted
        FramesDone++;
        return true;
    }
}

// A fake board used by --selftest: streams a test pattern to whoever sends it a hello.
class FakeBoard
{
    readonly UdpClient sock = new UdpClient(new IPEndPoint(IPAddress.Loopback, P.Port));
    public int DropLine = -1;            // if >= 0, never send this line (tests loss handling)
    public static ushort Pixel(int x, int y, int f) { return (ushort)((x * 7 + y * 3 + f * 11) & 0xFFFF); }

    public void SendFrames(int count)
    {
        IPEndPoint ep = null;
        byte[] hello = sock.Receive(ref ep);            // learn the viewer's address
        for (int f = 0; f < count; f++)
            for (int y = 0; y < P.H; y++)
            {
                if (y == DropLine && f == 1) continue;
                byte[] pkt = new byte[P.Hdr + P.LineBytes];
                BitConverter.GetBytes((uint)f).CopyTo(pkt, 0);
                BitConverter.GetBytes((ushort)y).CopyTo(pkt, 4);
                BitConverter.GetBytes((ushort)P.LineBytes).CopyTo(pkt, 6);
                for (int x = 0; x < P.W; x++)
                    BitConverter.GetBytes(Pixel(x, y, f)).CopyTo(pkt, P.Hdr + 2 * x);
                sock.Send(pkt, pkt.Length, ep);
                if ((y & 15) == 15) Thread.Sleep(1);     // keep the loopback buffer from overflowing
            }
        sock.Close();
    }
}

class Viewer : Form
{
    readonly PictureBox box = new PictureBox();
    readonly Bitmap bmp = new Bitmap(P.W, P.H, PixelFormat.Format16bppRgb565);
    readonly FrameAssembler asm = new FrameAssembler();
    readonly UdpClient sock = new UdpClient(0);
    readonly IPEndPoint board;
    int framesThisSec; long lastTick = Stopwatch.GetTimestamp();
    volatile bool run = true;

    Viewer(string ip)
    {
        board = new IPEndPoint(IPAddress.Parse(ip), P.Port);
        Text = "FPGA camera stream - waiting for " + ip;
        ClientSize = new Size(P.W, P.H);
        box.Dock = DockStyle.Fill; box.SizeMode = PictureBoxSizeMode.Zoom; box.BackColor = Color.Black;
        box.Image = bmp;
        Controls.Add(box);
        sock.Client.ReceiveBufferSize = 4 * 1024 * 1024;
        new Thread(Hello) { IsBackground = true }.Start();
        new Thread(Receive) { IsBackground = true }.Start();
        FormClosing += delegate { run = false; };
    }

    void Hello()
    {
        byte[] hi = new byte[] { (byte)'h', (byte)'i' };
        while (run) { try { sock.Send(hi, hi.Length, board); } catch { } Thread.Sleep(500); }
    }

    void Receive()
    {
        IPEndPoint any = new IPEndPoint(IPAddress.Any, 0);
        while (run)
        {
            byte[] pkt;
            try { pkt = sock.Receive(ref any); } catch { continue; }
            if (!asm.Add(pkt, pkt.Length)) continue;
            framesThisSec++;
            BitmapData d = bmp.LockBits(new Rectangle(0, 0, P.W, P.H), ImageLockMode.WriteOnly, PixelFormat.Format16bppRgb565);
            for (int y = 0; y < P.H; y++) Marshal.Copy(asm.Buf, y * P.LineBytes, d.Scan0 + y * d.Stride, P.LineBytes);
            bmp.UnlockBits(d);
            long now = Stopwatch.GetTimestamp();
            double secs = (now - lastTick) / (double)Stopwatch.Frequency;
            string t = null;
            if (secs >= 1.0) { t = string.Format("FPGA camera stream - {0:F1} fps, lines lost {1}", framesThisSec / secs, asm.LinesLost); framesThisSec = 0; lastTick = now; }
            try { BeginInvoke((Action)delegate { box.Invalidate(); if (t != null) Text = t; }); } catch { }
        }
    }

    static int SelfTest()
    {
        FakeBoard fb = new FakeBoard { DropLine = 100 };
        Thread t = new Thread(delegate() { fb.SendFrames(3); });
        t.Start();
        UdpClient c = new UdpClient(0);
        c.Client.ReceiveTimeout = 3000;
        c.Send(new byte[] { 1 }, 1, new IPEndPoint(IPAddress.Loopback, P.Port));
        FrameAssembler a = new FrameAssembler();
        IPEndPoint any = new IPEndPoint(IPAddress.Any, 0);
        int fails = 0, completed = 0, frameNo = 0;
        try
        {
            while (completed < 3)
            {
                byte[] pkt = c.Receive(ref any);
                if (!a.Add(pkt, pkt.Length)) continue;
                // frame 1 has line 100 missing (never sent), so skip checking that row
                int f = (int)BitConverter.ToUInt32(pkt, 0);
                for (int y = 0; y < P.H; y++)
                {
                    if (f == 1 && y == 100) continue;
                    for (int x = 0; x < P.W; x++)
                        if (BitConverter.ToUInt16(a.Buf, y * P.LineBytes + 2 * x) != FakeBoard.Pixel(x, y, f)) fails++;
                }
                completed++; frameNo = f;
            }
        }
        catch (SocketException) { Console.WriteLine("FAIL: timed out waiting for packets"); return 1; }
        t.Join();
        bool ok = fails == 0 && a.FramesDone == 3 && a.LinesLost == 1 && a.BadPackets == 0;
        Console.WriteLine("frames {0}, wrong pixels {1}, lines lost {2} (expected 1), bad packets {3}", a.FramesDone, fails, a.LinesLost, a.BadPackets);
        // malformed packets must be rejected, not crash
        FrameAssembler b = new FrameAssembler();
        ok &= !b.Add(new byte[10], 10) && !b.Add(new byte[P.Hdr + P.LineBytes], P.Hdr + P.LineBytes - 1) && b.BadPackets == 2;
        byte[] badLine = new byte[P.Hdr + P.LineBytes];
        BitConverter.GetBytes((ushort)P.H).CopyTo(badLine, 4);
        BitConverter.GetBytes((ushort)P.LineBytes).CopyTo(badLine, 6);
        ok &= !b.Add(badLine, badLine.Length) && b.BadPackets == 3;
        Console.WriteLine(ok ? "=== ALL CHECKS PASSED ===" : "=== FAILED ===");
        return ok ? 0 : 1;
    }

    [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--selftest") { AttachConsole(-1); return SelfTest(); }
        Application.EnableVisualStyles();
        Application.Run(new Viewer(args.Length > 0 ? args[0] : "192.168.1.10"));
        return 0;
    }
}
