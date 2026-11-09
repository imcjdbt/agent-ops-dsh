param(
  [Parameter(Mandatory=$true)][string]$Bg,
  [Parameter(Mandatory=$true)][string]$Ink,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

function HexToRgb([string]$h){
  $h = $h.TrimStart('#')
  @(
    [Convert]::ToInt32($h.Substring(0,2),16),
    [Convert]::ToInt32($h.Substring(2,2),16),
    [Convert]::ToInt32($h.Substring(4,2),16)
  )
}

$b = HexToRgb $Bg
$i = HexToRgb $Ink
$lum = (0.2126*$b[0] + 0.7152*$b[1] + 0.0722*$b[2]) / 255.0
$light = if($lum -gt 0.5){1}else{0}

$abgr = [uint32]([long]4278190080 + ([long]$i[2] -shl 16) + ([long]$i[1] -shl 8) + [long]$i[0])
$argb = [uint32]([long]3288334336 + ([long]$i[0] -shl 16) + ([long]$i[1] -shl 8) + [long]$i[2])

"bg=$Bg lum=$([math]::Round($lum,3)) light=$light ink=$Ink accent=$('{0:X8}' -f $abgr)"
if($DryRun){ "DRY RUN - nothing written"; exit 0 }

$pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
Set-ItemProperty $pers -Name AppsUseLightTheme -Value $light -Type DWord
Set-ItemProperty $pers -Name SystemUsesLightTheme -Value $light -Type DWord

# Windows 的「自动从背景选择强调色」会周期性地把强调色改回它自己算的值，关掉它
$desk = 'HKCU:\Control Panel\Desktop'
try {
  $auto = (Get-ItemProperty $desk -ErrorAction Stop).AutoColorization
  if ($auto -ne 0) { Set-ItemProperty $desk -Name AutoColorization -Value 0 -Type DWord; "auto-colorization: $auto -> 0" }
} catch { "auto-colorization: skip ($($_.Exception.Message.Split([Environment]::NewLine)[0]))" }

$dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
Set-ItemProperty $dwm -Name AccentColor -Value $abgr -Type DWord
Set-ItemProperty $dwm -Name AccentColorInactive -Value $abgr -Type DWord
Set-ItemProperty $dwm -Name ColorizationColor -Value $argb -Type DWord
Set-ItemProperty $dwm -Name ColorizationAfterglow -Value $argb -Type DWord
Set-ItemProperty $dwm -Name ColorPrevalence -Value 1 -Type DWord
Set-ItemProperty $dwm -Name EnableWindowColorization -Value 1 -Type DWord

# 开始菜单 / 部分系统界面读的是 Explorer\Accent 下的两个键
$acc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
if (Test-Path $acc) {
  try {
    Set-ItemProperty $acc -Name AccentColorMenu -Value $abgr -Type DWord
    Set-ItemProperty $acc -Name StartColorMenu  -Value $abgr -Type DWord
    "accent menu: synced"
  } catch { "accent menu: skip ($($_.Exception.Message.Split([Environment]::NewLine)[0]))" }
}

Add-Type -Namespace W -Name T -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct P { public uint c1; public uint c2; public uint b1; public uint b2; public uint blur; public uint glass; public uint opaque; }
[DllImport("dwmapi.dll")]
public static extern int DwmSetColorizationParameters(ref P p, uint flags);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
'@
$p = New-Object W.T+P
$p.c1 = $argb; $p.c2 = $argb
$p.blur = 1; $p.glass = 1; $p.opaque = 0
try {
  $rc = [W.T]::DwmSetColorizationParameters([ref]$p, 0)
  "dwm rc=$rc"
} catch {
  "dwm skip: " + $_.Exception.Message.Split([Environment]::NewLine)[0]
}
$r = [IntPtr]::Zero
[void][W.T]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
"ok dwm=$rc light=$light"
