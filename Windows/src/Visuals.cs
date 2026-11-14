using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AudioMixer
{
    /// dB-scaled peak meter: -60 dBFS … 0 dBFS maps to empty … full.
    public sealed class LevelMeter : FrameworkElement
    {
        public static readonly DependencyProperty LevelProperty = DependencyProperty.Register(
            "Level", typeof(double), typeof(LevelMeter),
            new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

        private static readonly Brush TrackBrush = Freeze(new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)));
        private static readonly Brush FillBrush = Freeze(MakeFill());

        public double Level
        {
            get { return (double)GetValue(LevelProperty); }
            set { SetValue(LevelProperty, value); }
        }

        private static Brush MakeFill()
        {
            // Cutroom's meter colours: cyan, then magenta, then red at the top.
            LinearGradientBrush brush = new LinearGradientBrush();
            brush.StartPoint = new Point(0, 0);
            brush.EndPoint = new Point(1, 0);
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0x1D, 0xD9, 0xF9), 0));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0x1D, 0xD9, 0xF9), 0.55));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0xF4, 0x5C, 0xF7), 0.85));
            brush.GradientStops.Add(new GradientStop(Color.FromRgb(0xE5, 0x53, 0x3F), 1));
            return brush;
        }

        private static Brush Freeze(Brush brush)
        {
            brush.Freeze();
            return brush;
        }

        protected override void OnRender(DrawingContext context)
        {
            double width = ActualWidth, height = ActualHeight;
            if (width <= 0 || height <= 0) return;
            double radius = height / 2;
            Rect full = new Rect(0, 0, width, height);
            context.DrawRoundedRectangle(TrackBrush, null, full, radius, radius);

            double level = Level;
            if (level <= 0) return;
            double decibels = 20 * Math.Log10(level);
            double fraction = Math.Min(1, Math.Max(0, (decibels + 60) / 60));
            if (fraction <= 0) return;
            double filled = Math.Max(height, width * fraction);
            context.PushClip(new RectangleGeometry(new Rect(0, 0, filled, height), radius, radius));
            context.DrawRectangle(FillBrush, null, full);
            context.Pop();
        }
    }

    /// The app icon is drawn in code so the build needs no image tools:
    /// three mixer faders in Cutroom's cyan, indigo and magenta on an ink tile.
    internal static class IconArt
    {
        public static BitmapSource Render(int size)
        {
            bool bold = size <= 32;   // fewer, heavier shapes survive at tray size
            DrawingVisual visual = new DrawingVisual();
            using (DrawingContext context = visual.RenderOpen())
            {
                double scale = size / 256.0;
                context.PushTransform(new ScaleTransform(scale, scale));

                LinearGradientBrush tile = new LinearGradientBrush(Color.FromRgb(0x1C, 0x1C, 0x22), Color.FromRgb(0x0A, 0x0A, 0x0B), 90);
                Pen edge = new Pen(new SolidColorBrush(Color.FromArgb(bold ? (byte)0x55 : (byte)0x2E, 0xFF, 0xFF, 0xFF)), bold ? 10 : 4);
                context.DrawRoundedRectangle(tile, edge, new Rect(6, 6, 244, 244), 58, 58);

                Color[] colors = { Color.FromRgb(0x1D, 0xD9, 0xF9), Color.FromRgb(0x7A, 0x6C, 0xFF), Color.FromRgb(0xFC, 0x2D, 0xFD) };
                double[] knobs = { 104, 158, 88 };
                double trackWidth = bold ? 22 : 12;
                double knobRadius = bold ? 27 : 21;
                double top = bold ? 50 : 58, bottom = bold ? 206 : 198;
                Brush rail = new SolidColorBrush(Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF));
                for (int i = 0; i < 3; i++)
                {
                    double x = 128 + (i - 1) * (bold ? 62 : 56);
                    Brush colour = new SolidColorBrush(colors[i]);
                    context.DrawRoundedRectangle(rail, null, new Rect(x - trackWidth / 2, top, trackWidth, bottom - top), trackWidth / 2, trackWidth / 2);
                    context.DrawRoundedRectangle(colour, null, new Rect(x - trackWidth / 2, knobs[i], trackWidth, bottom - knobs[i]), trackWidth / 2, trackWidth / 2);
                    context.DrawEllipse(colour, null, new Point(x, knobs[i]), knobRadius, knobRadius);
                    if (!bold) context.DrawEllipse(new SolidColorBrush(Color.FromRgb(0x0A, 0x0A, 0x0B)), null, new Point(x, knobs[i]), 8, 8);
                }
                context.Pop();
            }
            RenderTargetBitmap bitmap = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            bitmap.Freeze();
            return bitmap;
        }

        /// Writes a multi-size .ico: classic 32-bit bitmaps up to 64 px and a PNG for 256 px.
        public static byte[] IcoBytes()
        {
            int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 256 };
            List<byte[]> images = new List<byte[]>();
            foreach (int size in sizes) images.Add(size == 256 ? Png(Render(size)) : Dib(Render(size), size));

            using (MemoryStream output = new MemoryStream())
            using (BinaryWriter writer = new BinaryWriter(output))
            {
                writer.Write((short)0); writer.Write((short)1); writer.Write((short)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)0); writer.Write((byte)0);
                    writer.Write((short)1); writer.Write((short)32);
                    writer.Write(images[i].Length);
                    writer.Write(offset);
                    offset += images[i].Length;
                }
                foreach (byte[] image in images) writer.Write(image);
                writer.Flush();
                return output.ToArray();
            }
        }

        public static byte[] Png(BitmapSource source)
        {
            PngBitmapEncoder encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(source));
            using (MemoryStream stream = new MemoryStream())
            {
                encoder.Save(stream);
                return stream.ToArray();
            }
        }

        private static byte[] Dib(BitmapSource source, int size)
        {
            FormatConvertedBitmap straight = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
            int stride = size * 4;
            byte[] pixels = new byte[stride * size];
            straight.CopyPixels(pixels, stride, 0);
            int maskStride = ((size + 31) / 32) * 4;

            using (MemoryStream stream = new MemoryStream())
            using (BinaryWriter writer = new BinaryWriter(stream))
            {
                writer.Write(40); writer.Write(size); writer.Write(size * 2);
                writer.Write((short)1); writer.Write((short)32);
                writer.Write(0); writer.Write(pixels.Length + maskStride * size);
                writer.Write(0); writer.Write(0); writer.Write(0); writer.Write(0);
                for (int y = size - 1; y >= 0; y--) writer.Write(pixels, y * stride, stride);   // bottom-up
                writer.Write(new byte[maskStride * size]);                                    // alpha channel does the masking
                writer.Flush();
                return stream.ToArray();
            }
        }
    }

    /// Large, alpha-correct icons for other apps' executables.
    internal static class ShellIcon
    {
        public static BitmapSource Load(string path, int size)
        {
            try
            {
                BitmapSource image = FromShell(path, size);
                if (image != null) return image;
            }
            catch
            {
            }
            try
            {
                using (System.Drawing.Icon icon = System.Drawing.Icon.ExtractAssociatedIcon(path))
                {
                    if (icon == null) return null;
                    BitmapSource image = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                        icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    image.Freeze();
                    return image;
                }
            }
            catch
            {
                return null;
            }
        }

        private static BitmapSource FromShell(string path, int size)
        {
            Guid iid = typeof(IShellItemImageFactory).GUID;
            IShellItemImageFactory factory;
            if (Native.SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out factory) < 0 || factory == null) return null;
            IntPtr bitmap = IntPtr.Zero;
            try
            {
                NativeSize wanted = new NativeSize();
                wanted.Width = size; wanted.Height = size;
                if (factory.GetImage(wanted, 0x4, out bitmap) < 0 || bitmap == IntPtr.Zero) return null;   // SIIGBF_ICONONLY

                BitmapInfoHeader header = new BitmapInfoHeader();
                header.Size = Marshal.SizeOf(typeof(BitmapInfoHeader));
                header.Width = size; header.Height = -size;   // top-down
                header.Planes = 1; header.BitCount = 32;
                byte[] pixels = new byte[size * size * 4];
                IntPtr dc = Native.GetDC(IntPtr.Zero);
                int lines;
                try { lines = Native.GetDIBits(dc, bitmap, 0, size, pixels, ref header, 0); }
                finally { Native.ReleaseDC(IntPtr.Zero, dc); }
                if (lines != size) return null;

                // Icons without an alpha channel come back fully transparent; treat them as opaque.
                bool anyAlpha = false;
                for (int i = 3; i < pixels.Length; i += 4) if (pixels[i] != 0) { anyAlpha = true; break; }
                BitmapSource image = BitmapSource.Create(size, size, 96, 96,
                    anyAlpha ? PixelFormats.Pbgra32 : PixelFormats.Bgr32, null, pixels, size * 4);
                image.Freeze();
                return image;
            }
            finally
            {
                if (bitmap != IntPtr.Zero) Native.DeleteObject(bitmap);
                Marshal.ReleaseComObject(factory);
            }
        }
    }
}
