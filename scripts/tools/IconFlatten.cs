/*
 * 把分层图标（background + foreground）合成 AGC 要求的"直角图标"。
 * 分层图标的背景通常是圆角矩形，四角透明；应用商店会自己再套圆角蒙层，
 * 所以这里先把透明角落用邻近像素颜色补满，得到满幅方形图。
 *
 * 用法（PowerShell）:
 *   Add-Type -TypeDefinition ([IO.File]::ReadAllText('scripts\tools\IconFlatten.cs')) -ReferencedAssemblies System.Drawing
 *   [StoreIconBuilder]::Build($bg, $fg, $out, 1024)
 */
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class StoreIconBuilder
{
    public static void Build(string bgPath, string fgPath, string outPath, int size)
    {
        using (var bg = new Bitmap(bgPath))
        using (var fg = new Bitmap(fgPath))
        using (var flat = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        {
            // 丢掉原图标的圆角边与外发光：只取中心 82% 区域放大铺满，
            // 这样四周都是连续的底色，系统再套圆角蒙层不会露出任何边线
            double inset = 0.09;
            int sx = (int)(bg.Width * inset);
            int sy = (int)(bg.Height * inset);
            int sw = bg.Width - sx * 2;
            int sh = bg.Height - sy * 2;
            using (var g = Graphics.FromImage(flat))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(bg, new Rectangle(0, 0, size, size), new Rectangle(sx, sy, sw, sh), GraphicsUnit.Pixel);
            }
            ExtendEdges(flat, size);
            using (var g = Graphics.FromImage(flat))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(fg, 0, 0, size, size);
            }
            flat.Save(outPath, ImageFormat.Png);
        }
    }

    private static void ExtendEdges(Bitmap bmp, int size)
    {
        var rect = new Rectangle(0, 0, size, size);
        var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = data.Stride;
        byte[] buf = new byte[stride * size];
        Marshal.Copy(data.Scan0, buf, 0, buf.Length);

        // 水平：把每行两端（圆角外）用该行最外侧的不透明像素颜色延展
        for (int y = 0; y < size; y++)
        {
            int row = y * stride;
            int first = -1;
            for (int x = 0; x < size; x++)
            {
                if (buf[row + x * 4 + 3] >= 200) { first = x; break; }
            }
            if (first > 0)
            {
                for (int x = 0; x < first; x++) { CopyPixel(buf, row + x * 4, row + Math.Min(size - 1, first + 24) * 4); }
            }
            int last = -1;
            for (int x = size - 1; x >= 0; x--)
            {
                if (buf[row + x * 4 + 3] >= 200) { last = x; break; }
            }
            if (last >= 0 && last < size - 1)
            {
                for (int x = last + 1; x < size; x++) { CopyPixel(buf, row + x * 4, row + Math.Max(0, last - 24) * 4); }
            }
        }

        // 垂直：处理顶部/底部仍残留的透明像素
        for (int x = 0; x < size; x++)
        {
            int first = -1;
            for (int y = 0; y < size; y++)
            {
                if (buf[y * stride + x * 4 + 3] >= 200) { first = y; break; }
            }
            if (first > 0)
            {
                for (int y = 0; y < first; y++) { CopyPixel(buf, y * stride + x * 4, Math.Min(size - 1, first + 24) * stride + x * 4); }
            }
            int last = -1;
            for (int y = size - 1; y >= 0; y--)
            {
                if (buf[y * stride + x * 4 + 3] >= 200) { last = y; break; }
            }
            if (last >= 0 && last < size - 1)
            {
                for (int y = last + 1; y < size; y++) { CopyPixel(buf, y * stride + x * 4, Math.Max(0, last - 24) * stride + x * 4); }
            }
        }

        Marshal.Copy(buf, 0, data.Scan0, buf.Length);
        bmp.UnlockBits(data);
    }

    private static void CopyPixel(byte[] buf, int dst, int src)
    {
        buf[dst] = buf[src];
        buf[dst + 1] = buf[src + 1];
        buf[dst + 2] = buf[src + 2];
        buf[dst + 3] = 255;
    }
}
