using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

// Standalone community launcher. Compiled on a Windows GitHub Actions runner.
// Reads the VSCodium installation from App\VSCodium but stores editor data
// outside App, in Data\VSCodium. Nothing is moved at launch or exit.
internal static class VSCodiumPortableLauncher
{
    // Windows-compatible quoting, for file/folder names that include spaces.
    private static string QuoteArgument(string value)
    {
        if (value.Length > 0 && value.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            return value;
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char current in value)
        {
            if (current == '\\') { slashes++; continue; }
            if (current == '"')
            {
                result.Append('\\', slashes * 2 + 1);
                result.Append('"');
                slashes = 0;
                continue;
            }
            result.Append('\\', slashes);
            slashes = 0;
            result.Append(current);
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string baseDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string executable = Path.Combine(baseDir, @"App\VSCodium\VSCodium.exe");
            string innerData = Path.Combine(baseDir, @"App\VSCodium\data");
            string dataDir = Path.Combine(baseDir, @"Data\VSCodium");
            string tempDir = Path.Combine(dataDir, "tmp");
            if (!File.Exists(executable))
            {
                MessageBox.Show("Could not find App\\VSCodium\\VSCodium.exe.\nRe-extract the entire portable application.",
                    "VSCodium Portable", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
            if (Directory.Exists(innerData))
            {
                MessageBox.Show("An unexpected App\\VSCodium\\data folder was found.\n" +
                    "It may contain settings from an older portable build. Back up that folder and read the migration instructions before continuing.",
                    "VSCodium Portable: data migration required", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 3;
            }

            Directory.CreateDirectory(Path.Combine(dataDir, "user-data"));
            Directory.CreateDirectory(Path.Combine(dataDir, "extensions"));
            Directory.CreateDirectory(tempDir);

            var start = new ProcessStartInfo(executable);
            start.UseShellExecute = false;
            start.WorkingDirectory = Path.GetDirectoryName(executable);
            // Supported by the VS Code runtime: configurePortable() checks this
            // path and redirects editor user-data, extensions and temp files.
            start.EnvironmentVariables["VSCODE_PORTABLE"] = dataDir;
            start.EnvironmentVariables["TMP"] = tempDir;
            start.EnvironmentVariables["TEMP"] = tempDir;

            var arguments = new StringBuilder();
            foreach (string value in args)
            {
                if (arguments.Length > 0) arguments.Append(' ');
                arguments.Append(QuoteArgument(value));
            }
            start.Arguments = arguments.ToString();
            using (Process child = Process.Start(start))
            {
                if (child == null) return 4;
                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch (Exception failure)
        {
            MessageBox.Show(failure.Message, "VSCodium Portable", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
