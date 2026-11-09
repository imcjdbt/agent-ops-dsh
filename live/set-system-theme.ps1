param(
  [string]$Bg = '#030605',
  [string]$Ink = '#C3F8E2',
  [switch]$DryRun,
  [switch]$Restart
)

$ErrorActionPreference = 'Stop'

function HexToRgb([string]$h) {
  $h = $h.TrimStart('#')
  return @(
    [Convert]::ToInt32($h.Substring(0, 2), 16),
    [Convert]::ToInt32($h.Substring(2, 2), 16),
    [Convert]::ToInt32($h.Substring(4, 2), 16)
  )
}

function RgbToHsl($r, $g, $b) {
  $r = $r / 255.0; $g = $g / 255.0; $b = $b / 255.0
  $max = [Math]::Max($r, [Math]::Max($g, $b))
  $min = [Math]::Min($r, [Math]::Min($g, $b))
  $l = ($max + $min) / 2.0
  if ($max -eq $min) { return @(0.0, 0.0, $l) }
  $d = $max - $min
  if ($l -gt 0.5) { $s = $d / (2.0 - $max - $min) } else { $s = $d / ($max + $min) }
  if ($max -eq $r) {
    $h = (($g - $b) / $d) % 6.0
  } elseif ($max -eq $g) {
    $h = (($b - $r) / $d) + 2.0
  } else {
    $h = (($r - $g) / $d) + 4.0
  }
  $h = $h / 6.0
  if ($h -lt 0) { $h += 1.0 }
  return @($h, $s, $l)
}

function HslToRgb($h, $s, $l) {
  if ($s -eq 0) {
    $v = [int][Math]::Round($l * 255)
    return @($v, $v, $v)
  }
  if ($l -lt 0.5) { $q = $l * (1 + $s) } else { $q = $l + $s - ($l * $s) }
  $p = 2 * $l - $q
  $conv = {
    param($t)
    if ($t -lt 0) { $t += 1 }
    if ($t -gt 1) { $t -= 1 }
    if ($t -lt (1.0 / 6.0)) { return $p + ($q - $p) * 6 * $t }
    if ($t -lt 0.5) { return $q }
    if ($t -lt (2.0 / 3.0)) { return $p + ($q - $p) * (2.0 / 3.0 - $t) * 6 }
    return $p
  }
  $r = & $conv ($h + 1.0 / 3.0)
  $g = & $conv $h
  $b = & $conv ($h - 1.0 / 3.0)
  return @(
    [int][Math]::Round($r * 255),
    [int][Math]::Round($g * 255),
    [int][Math]::Round($b * 255)
  )
}

$bgRgb = HexToRgb $Bg
$lum = (0.2126 * $bgRgb[0] + 0.7152 * $bgRgb[1] + 0.0722 * $bgRgb[2]) / 255.0
$light = [int]($lum -gt 0.5)

$rgb = HexToRgb $Ink
$abgr = [uint32]([long]4278190080 + ([long]$rgb[2] -shl 16) + ([long]$rgb[1] -shl 8) + [long]$rgb[0])

$hsl = RgbToHsl $rgb[0] $rgb[1] $rgb[2]
$ph = $hsl[0]; $ps = $hsl[1]; $pl = $hsl[2]
$offsets = @(0.21, 0.10, -0.12, -0.20, -0.28, -0.38, -0.50, 0.0)
$palette = New-Object 'System.Collections.Generic.List[byte]'
foreach ($off in $offsets) {
  $l = $pl + $off
  if ($l -lt 0.04) { $l = 0.04 }
  if ($l -gt 0.97) { $l = 0.97 }
  $c = HslToRgb $ph $ps $l
  $palette.Add([byte]$c[2])   # B
  $palette.Add([byte]$c[1])   # G
  $palette.Add([byte]$c[0])   # R
  $palette.Add([byte]0)
}
$palBytes = $palette.ToArray()

"bg=$Bg lum=$([Math]::Round($lum,3)) -> light=$light ; ink=$Ink abgr=$('{0:X8}' -f $abgr)"
"palette=" + (($palBytes | ForEach-Object { $_.ToString('X2') }) -join ' ')

if ($DryRun) { "dry-run: nothing written"; return }

$pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path $pers)) { New-Item -Path $pers -Force | Out-Null }
Set-ItemProperty $pers -Name AppsUseLightTheme -Value $light -Type DWord
Set-ItemProperty $pers -Name SystemUsesLightTheme -Value $light -Type DWord

$desk = 'HKCU:\Control Panel\Desktop'
if ((Get-ItemProperty $desk -Name AutoColorization -ErrorAction SilentlyContinue).AutoColorization -ne 0) {
  Set-ItemProperty $desk -Name AutoColorization -Value 0 -Type DWord
  "auto-colorization: 1 -> 0"
}

$hives = @(
  'HKCU:\Software\Microsoft\Windows\DWM',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
)

foreach ($hive in $hives) {
  if (-not (Test-Path $hive)) { New-Item -Path $hive -Force | Out-Null }
  foreach ($n in @('AccentColor', 'AccentColorInactive', 'AccentColorMenu', 'StartColor', 'StartColorMenu', 'ColorizationColor', 'TaskbarColorOverride')) {
    Set-ItemProperty $hive -Name $n -Value $abgr -Type DWord
  }
  Set-ItemProperty $hive -Name ColorPrevalence -Value 1 -Type DWord
  Set-ItemProperty $hive -Name EnableWindowColorization -Value 1 -Type DWord
  Set-ItemProperty $hive -Name AccentPalette -Value $palBytes -Type Binary
}
"accent written: $('{0:X8}' -f $abgr) to 4 hives + palette"

Add-Type -Namespace W -Name B -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
'@
$r = [IntPtr]::Zero
[void][W.B]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
[void][W.B]::SendMessageTimeout([IntPtr]0xffff, 0x031A, [IntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$r)
"broadcast done"

if ($Restart) {
  $ex = Get-Process explorer -ErrorAction SilentlyContinue
  if ($ex) {
    "restarting explorer"
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    "explorer restarted"
  }
}
