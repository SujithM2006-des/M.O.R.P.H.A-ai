# The Windows microphone (recording) level: prints it, and with -Lower lowers
# it by that many points, never below -Floor. Used by the wake listener when
# speech clips (peaks at the very top of the range), which garbles what the
# offline recogniser hears.
# With -Max, a level above it is brought down to it (and left alone otherwise).
param([int]$Lower = 0, [int]$Floor = 50, [int]$Max = 0)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  int f(); int g(); int h(); int i();
  int SetMasterVolumeLevelScalar(float level, Guid ctx);
  int j();
  int GetMasterVolumeLevelScalar(out float level);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid id, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int f(); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
public static class JarvisMic {
  static IAudioEndpointVolume Vol() {
    var e = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
    IMMDevice d; e.GetDefaultAudioEndpoint(1, 1, out d);
    var iid = typeof(IAudioEndpointVolume).GUID; object o;
    d.Activate(ref iid, 23, IntPtr.Zero, out o);
    return (IAudioEndpointVolume)o;
  }
  public static float Get() { float l; Vol().GetMasterVolumeLevelScalar(out l); return l; }
  public static void Set(float l) { Vol().SetMasterVolumeLevelScalar(l, Guid.Empty); }
}
'@
$now = [math]::Round([JarvisMic]::Get() * 100)
if ($Max -gt 0 -and $now -gt $Max) {
  $now = $Max
  [JarvisMic]::Set([float]($now / 100))
}
if ($Lower -gt 0 -and $now -gt $Floor) {
  $now = [math]::Max($Floor, $now - $Lower)
  [JarvisMic]::Set([float]($now / 100))
}
$now
