using System.Diagnostics;
using System.Reflection;
using System.Runtime.Loader;

internal static class Program
{
    private static void Log(string message)
    {
        File.AppendAllText(Path.Combine(AppContext.BaseDirectory, "BeatLinkAutoConnect.log"),
            $"{DateTime.UtcNow:O} {message}{Environment.NewLine}");
    }

    private static int Main(string[] args)
    {
        try
        {
            Directory.SetCurrentDirectory(AppContext.BaseDirectory);
            using Process game = Process.GetProcessById(int.Parse(args[0]));

            Assembly client = AssemblyLoadContext.Default.LoadFromAssemblyPath(
                Path.Combine(AppContext.BaseDirectory, "BeatLink.dll"));
            Type auth = client.GetType("BeatLink.Web.Authentication", throwOnError: true)!;
            Type memory = client.GetType("BeatLink.Game.Memory", throwOnError: true)!;
            MethodInfo readToken = auth.GetMethod("ReadTokenFile", BindingFlags.Public | BindingFlags.Static)!;
            MethodInfo connect = memory.GetMethod("ApplyPatches", BindingFlags.Public | BindingFlags.Static,
                binder: null, types: [typeof(string)], modifiers: null)!;

            object token = readToken.Invoke(null, null)!;
            string accessToken = (string)token.GetType().GetProperty("AccessToken")!.GetValue(token)!;
            if (string.IsNullOrEmpty(accessToken))
            {
                Log("No saved login. Open BeatLink and log in first.");
                return 1;
            }
            DateTime expiresAt = (DateTime)token.GetType().GetProperty("ExpiresAt")!.GetValue(token)!;
            if (expiresAt <= DateTime.UtcNow)
            {
                Log("Saved login expired. Open BeatLink and log in again.");
                return 1;
            }

            while (true)
            {
                game.Refresh();
                if (game.HasExited)
                {
                    Log("Game exited before connecting.");
                    return 1;
                }
                if (game.MainWindowHandle != IntPtr.Zero) break;
                Thread.Sleep(1000);
            }
            connect.Invoke(null, [accessToken]);
            Log("Connect completed.");
            return 0;
        }
        catch (Exception exception)
        {
            // Exception messages and arguments may contain credentials.
            Exception cause = exception is TargetInvocationException { InnerException: not null } invocation
                ? invocation.InnerException! : exception;
            Log($"Connect failed: {cause.GetType().Name}");
            return 1;
        }
    }
}
