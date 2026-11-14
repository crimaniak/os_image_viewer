// ImageViewer.exe - tiny GUI-subsystem stub for Explorer's "Open with".
// Compiled at install time by install-windows.ps1 with the csc.exe that ships
// with .NET Framework 4.x. It exists so that:
//   * Explorer shows "Image Viewer" (from the version resource), not "Windows PowerShell";
//   * no console window flashes when an image is opened.
// It runs open-image.ps1 (next to this exe) hidden, passing all arguments through.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

[assembly: AssemblyTitle("Image Viewer")]
[assembly: AssemblyDescription("Browser-based image viewer launcher")]
[assembly: AssemblyProduct("Image Viewer")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class Program
{
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "open-image.ps1");
        string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");

        var cmd = new StringBuilder("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ");
        cmd.Append(Quote(script));
        foreach (string a in args)
        {
            cmd.Append(' ').Append(Quote(a));
        }

        var psi = new ProcessStartInfo(ps, cmd.ToString());
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        try
        {
            Process.Start(psi);
            return 0;
        }
        catch (Exception)
        {
            return 1;
        }
    }

    // Quote one argument for CommandLineToArgvW.
    static string Quote(string s)
    {
        if (s.Length > 0 && s.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return s;
        string escaped = Regex.Replace(s, @"(\\*)""", "$1$1\\\"");
        escaped = Regex.Replace(escaped, @"(\\+)$", "$1$1");
        return "\"" + escaped + "\"";
    }
}
