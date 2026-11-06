& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo      = 'https://raw.githubusercontent.com/gokiburinotasogare/sauna-de-laudos/main'
$root      = "$env:LOCALAPPDATA\Ferramentas"
$braveDir  = "$root\Brave"
$ahkDir    = "$root\AHK"
$dados     = "$root\BraveData"
$atalho    = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Brave.lnk"
$braveArgs = "--user-data-dir=`"$dados`" --no-first-run --no-default-browser-check --disable-features=AIChat,BraveVPN,BraveRewards,MediaRouter"
$extensoes = 'fcoeoabgfenejglbffodgkkbkcdhcgfn', 'eimadpbcbfnmbkopoojfekhnkhdbieeh'
$adv       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$ua        = @{ 'User-Agent' = 'sauna-de-laudos' }
$estado    = @{ falhas = 0 }

function Passo([string]$nome, [scriptblock]$acao) {
    try {
        $info = & $acao
        Write-Host "  [ok] $nome $(if ($info) { "($info)" })" -ForegroundColor Green
    } catch {
        $estado.falhas++
        Write-Host "  [x]  ${nome}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Reg([string]$chave, [hashtable]$valores, [string]$tipo = 'DWord') {
    if (-not (Test-Path $chave)) { New-Item $chave -Force | Out-Null }
    foreach ($n in $valores.Keys) { New-ItemProperty $chave $n -Value $valores[$n] -PropertyType $tipo -Force | Out-Null }
}

function Parar([string]$pasta) {
    Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($pasta, 'OrdinalIgnoreCase') } | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

function Release([string]$projeto, [scriptblock]$arquivo) {
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/$projeto/releases/latest" -Headers $ua
        $a = $r.assets | Where-Object name -eq (& $arquivo $r.tag_name)
        return @{ Tag = $r.tag_name; Url = $a.browser_download_url; Sha = $a.digest -replace '^sha256:' }
    } catch {
        $req = [Net.HttpWebRequest]::Create("https://github.com/$projeto/releases/latest")
        $req.AllowAutoRedirect = $false
        $req.UserAgent = $ua['User-Agent']
        $resp = $req.GetResponse(); $tag = $resp.Headers['Location'].Split('/')[-1]; $resp.Close()
        $url = "https://github.com/$projeto/releases/download/$tag/$(& $arquivo $tag)"
        $sha = try { ((Invoke-RestMethod "$url.sha256" -Headers $ua) -split '\s+')[0] } catch { $null }
        return @{ Tag = $tag; Url = $url; Sha = $sha }
    }
}

function Mesclar($base, $novo) {
    foreach ($p in $novo.PSObject.Properties) {
        $atual = $base.PSObject.Properties[$p.Name]
        if ($atual -and $atual.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) { Mesclar $atual.Value $p.Value }
        else { $base | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
}

function Instalar([string]$projeto, [scriptblock]$arquivo, [string]$destino) {
    $rel = Release $projeto $arquivo
    $marca = "$destino\versao.txt"
    if ((Test-Path $marca) -and (Get-Content $marca) -eq $rel.Tag) { return $rel.Tag }
    $zip = "$destino.zip"
    Invoke-WebRequest $rel.Url -OutFile $zip -UseBasicParsing -Headers $ua
    if ($rel.Sha -and (Get-FileHash $zip).Hash -ne $rel.Sha) { Remove-Item $zip; throw 'SHA256 nao confere' }
    Parar $destino
    if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
    New-Item -ItemType Directory $destino | Out-Null
    tar -xf $zip -C $destino
    if ($LASTEXITCODE) { throw 'falha ao extrair' }
    Remove-Item $zip
    Set-Content $marca $rel.Tag
    "$($rel.Tag) instalado"
}

Write-Host "`n  Sauna de Laudos`n" -ForegroundColor Cyan
New-Item -ItemType Directory -Force $root, "$root\Downloads" | Out-Null

Passo 'Modo escuro' {
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' @{ AppsUseLightTheme = 0; SystemUsesLightTheme = 0 }
}

Passo 'Barra de tarefas' {
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' @{ SearchboxTaskbarMode = 0; BingSearchEnabled = 0 }
    Reg $adv @{ ShowTaskViewButton = 0; ShowCopilotButton = 0; TaskbarMn = 0; TaskbarSd = 0; MMTaskbarEnabled = 0 }
}

Passo 'Desafixar' {
    $n = 0
    foreach ($app in (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items()) {
        $app.Verbs() | Where-Object { ($_.Name -replace '&') -match 'Unpin from taskbar|Desafixar da barra de tarefas' } | ForEach-Object { $_.DoIt(); $n++ }
    }
    "$n itens"
}

Passo 'Bandeja' {
    Get-ChildItem 'HKCU:\Control Panel\NotifyIconSettings' -ErrorAction SilentlyContinue | ForEach-Object { Set-ItemProperty $_.PSPath IsPromoted 0 }
}

Passo 'Iniciar e dicas' {
    Reg $adv @{ Start_TrackDocs = 0; Start_TrackProgs = 0; Start_IrisRecommendations = 0; Start_AccountNotifications = 0; Start_Layout = 1; HideFileExt = 0; LaunchTo = 1 }
    $cdm = @{}
    'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-338393Enabled',
    'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
    'RotatingLockScreenOverlayEnabled' | ForEach-Object { $cdm[$_] = 0 }
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $cdm
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' @{ ScoobeSystemSettingEnabled = 0 }
    Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' @{ Flags = '506' } String
    Reg 'HKCU:\Software\Microsoft\Clipboard' @{ EnableClipboardHistory = 1 }
}

Passo 'Arquivos' {
    foreach ($f in 'main.ahk', 'cleanup.ps1', 'brave/initial_preferences', 'assets/wallpaper.jpg') {
        Invoke-WebRequest "$repo/$f" -OutFile "$root\$(Split-Path $f -Leaf)" -UseBasicParsing -Headers $ua
    }
}

Passo 'Brave' { Instalar 'brave/brave-browser' { param($t) "brave-$t-win32-x64.zip" } $braveDir }

Passo 'Config do Brave' {
    $prefs = (Get-Content "$root\initial_preferences" -Raw).Replace('__DOWNLOADS__', "$root\Downloads".Replace('\', '\\'))
    [IO.File]::WriteAllText("$braveDir\initial_preferences", $prefs)
    foreach ($id in $extensoes) {
        Reg "HKCU:\Software\Google\Chrome\Extensions\$id" @{ update_url = 'https://clients2.google.com/service/update2/crx' } String
    }
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($atalho)
    $lnk.TargetPath = "$braveDir\brave.exe"
    $lnk.Arguments = $braveArgs
    $lnk.Save()

    $arq = "$dados\Default\Preferences"
    $info = 'perfil existente'
    if (-not (Test-Path $arq)) {
        New-Item -ItemType Directory -Force $dados | Out-Null
        [IO.File]::WriteAllText("$dados\Local State", '{"brave":{"p3a":{"enabled":false,"notice_acknowledged":true}}}')
        Start-Process "$braveDir\brave.exe" "$($braveArgs.Replace('--no-first-run ', '')) about:blank" -WindowStyle Hidden
        $t = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path $arq) -and $t.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 300 }
        Start-Sleep -Seconds 3
        if (-not (Test-Path $arq)) { Parar $braveDir; throw 'perfil nao criado' }
        $info = 'perfil novo'
    }
    # o initial_preferences nao e confiavel; escreve as prefs direto no perfil, com o Brave fechado
    Parar $braveDir
    $base = [IO.File]::ReadAllText($arq) | ConvertFrom-Json
    $novo = $prefs | ConvertFrom-Json
    $novo.PSObject.Properties.Remove('distribution')
    Mesclar $base $novo
    [IO.File]::WriteAllText($arq, ($base | ConvertTo-Json -Depth 100 -Compress))
    "$info, prefs aplicadas"
}

Passo 'AutoHotkey' {
    Parar $ahkDir
    Instalar 'AutoHotkey/AutoHotkey' { param($t) "AutoHotkey_$($t.TrimStart('v')).zip" } $ahkDir
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' @{ SaunaDeLaudos = "`"$ahkDir\AutoHotkey64.exe`" `"$root\main.ahk`"" } String
}

Passo 'Explorer' {
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }
}

Passo 'Wallpaper' {
    Start-Sleep -Seconds 3   # depois do restart do Explorer, que reaplica o fundo da TI
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    [System.Drawing.Graphics]::FromImage($bmp).Clear([System.Drawing.Color]::Black)
    $bmp.Save("$root\preto.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    if (-not ('Sauna.Fundo' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace Sauna {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IDesktopWallpaper {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor, [MarshalAs(UnmanagedType.LPWStr)] string path);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitor);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint index);
        uint GetMonitorDevicePathCount();
        Rect GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitor);
        void SetBackgroundColor(uint color);
        uint GetBackgroundColor();
        void SetPosition(int position);
    }
    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")] public class DesktopWallpaper {}
    public static class Fundo {
        public static int Aplicar(string principal, string demais) {
            var w = (IDesktopWallpaper)new DesktopWallpaper();
            w.SetBackgroundColor(0);
            w.SetPosition(4);
            int n = 0;
            for (uint i = 0; i < w.GetMonitorDevicePathCount(); i++) {
                string id = w.GetMonitorDevicePathAt(i);
                Rect r;
                try { r = w.GetMonitorRECT(id); } catch { continue; }
                w.SetWallpaper(id, r.Left == 0 && r.Top == 0 ? principal : demais);
                n++;
            }
            return n;
        }
    }
}
'@
    }
    "$([Sauna.Fundo]::Aplicar("$root\wallpaper.jpg", "$root\preto.png")) monitores"
}

Passo 'Iniciar' {
    Start-Process "$ahkDir\AutoHotkey64.exe" "`"$root\main.ahk`""
    Start-Process "$braveDir\brave.exe" $braveArgs
}

if ($estado.falhas) { Write-Host "`n  Pronto, com $($estado.falhas) falha(s).`n" -ForegroundColor Yellow }
else { Write-Host "`n  Pronto.`n" -ForegroundColor Cyan }
}
