$ErrorActionPreference = 'SilentlyContinue'
$root = "$env:LOCALAPPDATA\Ferramentas"
$themes = "$env:APPDATA\Microsoft\Windows\Themes"

for ($i = 0; $i -lt 20; $i++) {
    $p = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($root, 'OrdinalIgnoreCase') }
    if (-not $p) { break }
    $p | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

try {
    Add-Type -Namespace Sauna -Name Spi -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int SystemParametersInfo(int a, int b, string c, int d);'
    [Sauna.Spi]::SystemParametersInfo(0x14, 0, "$env:WINDIR\Web\Wallpaper\Windows\img0.jpg", 3) | Out-Null
} catch {}

try {
    $clip = [Windows.ApplicationModel.DataTransfer.Clipboard, Windows.ApplicationModel.DataTransfer, ContentType = WindowsRuntime]
    $clip::ClearHistory() | Out-Null
    $clip::Clear()
} catch {}

Remove-Item -Recurse -Force -Path @(
    "$env:APPDATA\Microsoft\Windows\Recent\*"
    "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Brave.lnk"
    "$themes\Transcoded_*"
    "$themes\CachedFiles\*"
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    'HKCU:\Software\Google\Chrome\Extensions\fcoeoabgfenejglbffodgkkbkcdhcgfn'
    'HKCU:\Software\Google\Chrome\Extensions\eimadpbcbfnmbkopoojfekhnkhdbieeh'
)
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' SaunaDeLaudos

if ($env:LOCALAPPDATA -and (Split-Path $root) -eq $env:LOCALAPPDATA) {
    for ($i = 0; $i -lt 10 -and (Test-Path $root); $i++) {
        Remove-Item $root -Recurse -Force
        if (Test-Path $root) { Start-Sleep -Seconds 1 }
    }
}

Clear-RecycleBin -Force

if ($modo -eq 'desligar') {
    if (@(quser 2>$null).Count -eq 2) {
        shutdown.exe /s /t 0
        if (-not $LASTEXITCODE) { exit }
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show('Outra pessoa pode estar logada neste PC. Vou só fazer logoff.', 'Sauna de Laudos') | Out-Null
    }
}
shutdown.exe /l
