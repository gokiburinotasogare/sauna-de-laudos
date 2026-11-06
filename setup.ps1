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
$estado    = @{ ok = 0; avisos = 0; falhas = 0; aviso = $false; det = New-Object System.Collections.Generic.List[object]; log = "$root\sauna.log" }
$relogio   = [Diagnostics.Stopwatch]::StartNew()
$snapDir   = "$root\snapshot"
$snapArq   = "$snapDir\snapshot.json"
$snap      = @{ inicio = $null; historico = $null; valores = @{}; chaves = @{}; criadas = @(); pastas = @{}; arquivos = @{}; wallpaper = $null }

# ---------------------------------------------------------------- saida

function Log([string]$t) { try { Add-Content -Path $estado.log -Value $t -Encoding UTF8 } catch {} }
function Det([string]$t, [string]$cor = 'DarkGray') { $estado.det.Add([pscustomobject]@{ Texto = $t; Cor = $cor }) }
function Aviso([string]$t) { $estado.aviso = $true; Det $t 'Yellow' }

function Secao([string]$t) {
    Write-Host ''
    Write-Host '  ~~ ' -ForegroundColor DarkMagenta -NoNewline
    Write-Host $t -ForegroundColor Magenta
    Log "`n== $t"
}

function Passo([string]$nome, [scriptblock]$acao) {
    $estado.det.Clear(); $estado.aviso = $false
    $t = [Diagnostics.Stopwatch]::StartNew()
    $erro = $null; $info = $null
    try { $info = & $acao } catch { $erro = $_ }
    try { SalvarSnapshot } catch { if (-not $erro) { $erro = $_ } }
    $ms = $t.ElapsedMilliseconds
    $tempo = if ($ms -ge 1000) { '{0:N1} s' -f ($ms / 1000) } else { "$ms ms" }
    $rotulo = if ($info -and -not $erro) { "$nome ($info)" } else { $nome }
    $pontos = '.' * [Math]::Max(2, 46 - $rotulo.Length)

    if ($erro)             { $tag = '[xx]'; $cor = 'Red';    $estado.falhas++ }
    elseif ($estado.aviso) { $tag = '[!!]'; $cor = 'Yellow'; $estado.avisos++ }
    else                   { $tag = '[ok]'; $cor = 'Green';  $estado.ok++ }

    Write-Host "  $tag " -ForegroundColor $cor -NoNewline
    Write-Host "$rotulo " -NoNewline
    Write-Host "$pontos $tempo" -ForegroundColor DarkGray
    Log "$tag $rotulo ($tempo)"
    foreach ($d in $estado.det) {
        Write-Host "        | $($d.Texto)" -ForegroundColor $d.Cor
        Log "     | $($d.Texto)"
    }
    if ($erro) {
        Write-Host "        | $($erro.Exception.Message)" -ForegroundColor Red
        $inv = $erro.InvocationInfo
        if ($inv -and $inv.Line) { Write-Host "        | linha $($inv.ScriptLineNumber): $($inv.Line.Trim())" -ForegroundColor DarkRed }
        Log ($erro | Out-String)
        Log $erro.ScriptStackTrace
    }
}

# ---------------------------------------------------------------- snapshot
# Guarda como tudo estava ANTES do primeiro setup; o cleanup.ps1 devolve exatamente isso.
# Rodar o setup de novo nao sobrescreve o que ja foi anotado.

function CarregarSnapshot {
    if (-not (Test-Path $snapArq)) { return $false }
    $s = [IO.File]::ReadAllText($snapArq) | ConvertFrom-Json
    $snap.inicio = if ($s.inicio -is [datetime]) { $s.inicio.ToString('o') } else { $s.inicio }; $snap.historico = $s.historico; $snap.wallpaper = $s.wallpaper
    $snap.criadas = @($s.criadas | Where-Object { $_ })
    foreach ($v in @($s.valores))  { if ($v) { $snap.valores[$v.id] = $v } }
    foreach ($c in @($s.chaves))   { if ($c) { $snap.chaves[$c.chave] = $c } }
    foreach ($p in @($s.pastas))   { if ($p) { $snap.pastas[$p.id] = $p } }
    foreach ($a in @($s.arquivos)) { if ($a) { $snap.arquivos[$a.id] = $a } }
    $true
}

function SalvarSnapshot {
    if (-not (Test-Path $snapDir)) { return }
    $obj = [pscustomobject]@{
        inicio = $snap.inicio; historico = $snap.historico; wallpaper = $snap.wallpaper; criadas = @($snap.criadas)
        valores = @($snap.valores.Values); chaves = @($snap.chaves.Values); pastas = @($snap.pastas.Values); arquivos = @($snap.arquivos.Values)
    }
    [IO.File]::WriteAllText($snapArq, ($obj | ConvertTo-Json -Depth 10))
}

function LerValor($k, [string]$nome) {
    [pscustomobject]@{ nome = $nome; valor = $k.GetValue($nome, $null, 'DoNotExpandEnvironmentNames'); tipo = $k.GetValueKind($nome).ToString() }
}

# um valor isolado do registro
function AnotarValor([string]$chave, [string]$nome) {
    $id = "$chave|$nome"
    if ($snap.valores.ContainsKey($id)) { return }
    $k = Get-Item -LiteralPath $chave -ErrorAction SilentlyContinue
    $e = [pscustomobject]@{ id = $id; chave = $chave; nome = $nome; existia = $false; valor = $null; tipo = $null }
    if ($k -and ($k.GetValueNames() -contains $nome)) { $v = LerValor $k $nome; $e.existia = $true; $e.valor = $v.valor; $e.tipo = $v.tipo }
    $snap.valores[$id] = $e
}

# a chave inteira (todos os valores), pra coisas como a barra fixada e o historico do Win+R
function AnotarChave([string]$chave) {
    if ($snap.chaves.ContainsKey($chave)) { return }
    $k = Get-Item -LiteralPath $chave -ErrorAction SilentlyContinue
    $vals = @(); if ($k) { foreach ($n in $k.GetValueNames()) { if ($n) { $vals += LerValor $k $n } } }
    $snap.chaves[$chave] = [pscustomobject]@{ chave = $chave; existia = [bool]$k; valores = $vals }
}

# se a chave nao existe, anota o ancestral mais alto que vai ser criado, pra apagar depois
function AnotarCriacao([string]$chave) {
    $c = $chave; $alvo = $null
    while ($c -and -not (Test-Path -LiteralPath $c)) { $alvo = $c; $c = Split-Path $c }
    if ($alvo -and $snap.criadas -notcontains $alvo) { $snap.criadas += $alvo }
}

function AnotarPasta([string]$id, [string]$pasta) {
    if ($snap.pastas.ContainsKey($id)) { return }
    $existia = Test-Path -LiteralPath $pasta
    if ($existia) { robocopy $pasta "$snapDir\$id" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null }
    $snap.pastas[$id] = [pscustomobject]@{ id = $id; pasta = $pasta; existia = $existia }
}

function AnotarArquivo([string]$id, [string]$arquivo) {
    if ($snap.arquivos.ContainsKey($id)) { return }
    $existia = Test-Path -LiteralPath $arquivo
    if ($existia) { Copy-Item -LiteralPath $arquivo "$snapDir\$id" -Force }
    $snap.arquivos[$id] = [pscustomobject]@{ id = $id; arquivo = $arquivo; existia = $existia }
}

# ---------------------------------------------------------------- utilidades

function Reg([string]$chave, [hashtable]$valores, [string]$tipo = 'DWord') {
    AnotarCriacao $chave
    foreach ($n in $valores.Keys) { AnotarValor $chave $n }
    if (-not (Test-Path -LiteralPath $chave)) { New-Item $chave -Force | Out-Null }
    foreach ($n in $valores.Keys) { New-ItemProperty -LiteralPath $chave -Name $n -Value $valores[$n] -PropertyType $tipo -Force | Out-Null }
}

function CarregarTela {
    if (-not ('SaunaTela.Tela' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText("$root\tela.cs")) }
}

function Rodando([string]$pasta) { @(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($pasta, 'OrdinalIgnoreCase') }) }

function Parar([string]$pasta) {
    $p = Rodando $pasta
    if ($p) { $p | Stop-Process -Force; Start-Sleep -Milliseconds 800; Det "fechei $($p.Count) processo(s) que estavam abertos" }
}

function Release([string]$projeto, [scriptblock]$arquivo) {
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/$projeto/releases/latest" -Headers $ua
        $a = $r.assets | Where-Object name -eq (& $arquivo $r.tag_name)
        return @{ Tag = $r.tag_name; Url = $a.browser_download_url; Sha = $a.digest -replace '^sha256:' }
    } catch {
        Det 'API do GitHub indisponivel, descobrindo a versao pelo redirect'
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
    if ((Test-Path $marca) -and (Get-Content $marca) -eq $rel.Tag) { Det 'ja estava na versao mais recente'; return "$($rel.Tag)" }
    $zip = "$destino.zip"
    Invoke-WebRequest $rel.Url -OutFile $zip -UseBasicParsing -Headers $ua
    Det ('baixado: {0:N1} MB' -f ((Get-Item $zip).Length / 1MB))
    if ($rel.Sha) {
        if ((Get-FileHash $zip).Hash -ne $rel.Sha) { Remove-Item $zip; throw 'SHA256 nao confere' }
        Det 'sha256 conferido'
    } else { Aviso 'release sem sha256 publicado, nao deu pra conferir o download' }
    Parar $destino
    if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
    New-Item -ItemType Directory $destino | Out-Null
    tar -xf $zip -C $destino
    if ($LASTEXITCODE) { throw 'falha ao extrair' }
    Remove-Item $zip
    Set-Content $marca $rel.Tag
    "$($rel.Tag) instalado"
}

# ---------------------------------------------------------------- banner

$banner = @'
           )   )   )
          (   (   (
           )   )   )
                                __      __             __
  ___ ___ ___ _____  ___ _  ___/ /__   / /__ ___ _____/ /__  ___
 (_-</ _ `/ // / _ \/ _ `/ / _  / -_) / / _ `/ // / _  / _ \(_-<
/___/\_,_/\_,_/_//_/\_,_/  \_,_/\__/ /_/\_,_/\_,_/\_,_/\___/___/
'@ -split "`r?`n"
$cores = 'DarkGray', 'DarkGray', 'DarkGray', 'DarkMagenta', 'DarkMagenta', 'Magenta', 'Magenta', 'Cyan'

Write-Host ''
for ($i = 0; $i -lt $banner.Count; $i++) { Write-Host "  $($banner[$i])" -ForegroundColor $cores[$i] }
Write-Host ''
Write-Host ("  {0}  |  {1}  |  ps {2}  |  {3:dd/MM HH:mm}" -f $env:COMPUTERNAME, $env:USERNAME, "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)", (Get-Date)) -ForegroundColor DarkGray
Write-Host ('  ' + ('-' * 64)) -ForegroundColor DarkGray

New-Item -ItemType Directory -Force $root, "$root\Downloads" | Out-Null
Set-Content -Path $estado.log -Value "sauna de laudos - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $env:COMPUTERNAME\$env:USERNAME - ps $($PSVersionTable.PSVersion)" -Encoding UTF8

# ---------------------------------------------------------------- snapshot

Secao 'snapshot'

Passo 'Estado original' {
    New-Item -ItemType Directory -Force $snapDir | Out-Null
    if (CarregarSnapshot) {
        Det "ja existe um snapshot de $($snap.inicio); mantive o original"
        return 'reaproveitado'
    }
    $snap.inicio = (Get-Date).ToString('o')
    $hist = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    $snap.historico = if (Test-Path $hist) { @(Get-Content $hist).Count } else { 0 }
    AnotarPasta 'recentes' "$env:APPDATA\Microsoft\Windows\Recent"
    AnotarPasta 'fixados' "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    AnotarChave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
    AnotarChave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    AnotarArquivo 'Brave.lnk' $atalho
    foreach ($n in 'Wallpaper', 'WallpaperStyle', 'TileWallpaper') { AnotarValor 'HKCU:\Control Panel\Desktop' $n }
    Det 'recentes, barra fixada, historico do Win+R e do PowerShell'
    Det "o cleanup devolve tudo como estava; guardado em $snapDir"
    'novo'
}

# ---------------------------------------------------------------- windows

Secao 'windows'

Passo 'Modo escuro' {
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' @{ AppsUseLightTheme = 0; SystemUsesLightTheme = 0 }
    Det 'apps e sistema no escuro (aparece depois do restart do Explorer)'
}

Passo 'Barra de tarefas' {
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' @{ SearchboxTaskbarMode = 0; BingSearchEnabled = 0 }
    Reg $adv @{ ShowTaskViewButton = 0; ShowCopilotButton = 0; TaskbarMn = 0; TaskbarSd = 0; MMTaskbarEnabled = 0 }
    Det 'sem busca, visao de tarefas, copilot e chat'
    Det 'barra so no monitor principal'
}

Passo 'Desafixar' {
    $nomes = @()
    foreach ($app in (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items()) {
        $v = $app.Verbs() | Where-Object { ($_.Name -replace '&') -match 'Unpin from taskbar|Desafixar da barra de tarefas' }
        if ($v) { $v | ForEach-Object { $_.DoIt() }; $nomes += $app.Name }
    }
    if ($nomes) { Det "tirei: $($nomes -join ', ')" } else { Det 'a barra ja estava limpa' }
    "$($nomes.Count) itens"
}

Passo 'Bandeja' {
    $itens = @(Get-ChildItem 'HKCU:\Control Panel\NotifyIconSettings' -ErrorAction SilentlyContinue)
    $itens | ForEach-Object { Reg $_.PSPath @{ IsPromoted = 0 } }
    "$($itens.Count) icones escondidos"
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
    Det 'sem recentes, recomendacoes, dicas e propagandas'
    Det 'extensoes de arquivo visiveis, Explorer abre em Este Computador'
    Det 'historico da area de transferencia ligado (Win+V)'
}

# ---------------------------------------------------------------- arquivos

Secao 'arquivos'

Passo 'Download do repo' {
    $lista = 'main.ahk', 'cleanup.ps1', 'tela.cs', 'brave/initial_preferences', 'assets/wallpaper.jpg'
    foreach ($f in $lista) {
        $dest = "$root\$(Split-Path $f -Leaf)"
        Invoke-WebRequest "$repo/$f" -OutFile $dest -UseBasicParsing -Headers $ua
        Det ('{0,-22} {1,7:N0} KB' -f (Split-Path $f -Leaf), ((Get-Item $dest).Length / 1KB))
    }
    "$($lista.Count) arquivos"
}

# ---------------------------------------------------------------- brave

Secao 'brave'

Passo 'Brave' { Instalar 'brave/brave-browser' { param($t) "brave-$t-win32-x64.zip" } $braveDir }

Passo 'Config do Brave' {
    $prefs = (Get-Content "$root\initial_preferences" -Raw).Replace('__DOWNLOADS__', "$root\Downloads".Replace('\', '\\'))
    [IO.File]::WriteAllText("$braveDir\initial_preferences", $prefs)
    foreach ($id in $extensoes) {
        Reg "HKCU:\Software\Google\Chrome\Extensions\$id" @{ update_url = 'https://clients2.google.com/service/update2/crx' } String
    }
    Det "$($extensoes.Count) extensoes agendadas (instalam ao abrir o Brave)"
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($atalho)
    $lnk.TargetPath = "$braveDir\brave.exe"
    $lnk.Arguments = $braveArgs
    $lnk.Save()
    Det 'atalho no menu Iniciar'

    $arq = "$dados\Default\Preferences"
    $info = 'perfil existente'
    if (-not (Test-Path $arq)) {
        New-Item -ItemType Directory -Force $dados | Out-Null
        [IO.File]::WriteAllText("$dados\Local State", '{"brave":{"p3a":{"enabled":false,"notice_acknowledged":true}}}')
        Start-Process "$braveDir\brave.exe" "$($braveArgs.Replace('--no-first-run ', '')) about:blank" -WindowStyle Hidden
        $t = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path $arq) -and $t.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 300 }
        Start-Sleep -Seconds 3
        if (-not (Test-Path $arq)) { Parar $braveDir; throw 'o Brave nao criou o perfil em 30 s' }
        Det ('perfil criado em {0:N1} s' -f $t.Elapsed.TotalSeconds)
        $info = 'perfil novo'
    }
    # o initial_preferences nao e confiavel; escreve as prefs direto no perfil, com o Brave fechado
    Parar $braveDir
    $base = [IO.File]::ReadAllText($arq) | ConvertFrom-Json
    $novo = $prefs | ConvertFrom-Json
    $novo.PSObject.Properties.Remove('distribution')
    Mesclar $base $novo
    [IO.File]::WriteAllText($arq, ($base | ConvertTo-Json -Depth 100 -Compress))
    Det 'prefs gravadas: fundo gradiente, sem VPN, Wallet, Leo, News e Rewards'
    $info
}

# ---------------------------------------------------------------- autohotkey

Secao 'autohotkey'

Passo 'AutoHotkey' {
    Parar $ahkDir
    $r = Instalar 'AutoHotkey/AutoHotkey' { param($t) "AutoHotkey_$($t.TrimStart('v')).zip" } $ahkDir
    Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' @{ SaunaDeLaudos = "`"$ahkDir\AutoHotkey64.exe`" `"$root\main.ahk`"" } String
    Det 'inicia junto com o Windows'
    $r
}

# ---------------------------------------------------------------- aplicar

Secao 'aplicar'

Passo 'Explorer' {
    # so o Explorer desta sessao; com outras pessoas logadas, matar todos da acesso negado
    $sessao = (Get-Process -Id $PID).SessionId
    $outras = @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -ne $sessao).Count
    if ($outras) { Det "$outras outra(s) pessoa(s) logada(s) neste PC, nao mexi nelas" }
    $meu = { Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $sessao }
    & $meu | Stop-Process -Force
    $t = [Diagnostics.Stopwatch]::StartNew()
    while (-not (& $meu) -and $t.Elapsed.TotalSeconds -lt 8) { Start-Sleep -Milliseconds 500 }
    if (& $meu) { Det ('voltou sozinho em {0:N1} s' -f $t.Elapsed.TotalSeconds) }
    else { Start-Process explorer; Det 'nao voltou sozinho, abri de novo' }
    Start-Sleep -Seconds 2
}

Passo 'Wallpaper' {
    Start-Sleep -Seconds 3   # depois do restart do Explorer, que reaplica o fundo da TI
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    [System.Drawing.Graphics]::FromImage($bmp).Clear([System.Drawing.Color]::Black)
    $bmp.Save("$root\preto.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    CarregarTela
    if (-not $snap.wallpaper) {
        $telas = @([SaunaTela.Tela]::Ler() | ForEach-Object { $x = $_ -split "`t", 2; [pscustomobject]@{ id = $x[0]; caminho = $x[1] } })
        $snap.wallpaper = [pscustomobject]@{ posicao = [SaunaTela.Tela]::Posicao(); cor = [SaunaTela.Tela]::Cor(); telas = $telas }
        Det "fundo original anotado ($($telas.Count) telas)"
    }
    $linhas = [SaunaTela.Tela]::Aplicar("$root\wallpaper.jpg", "$root\preto.png")
    foreach ($l in $linhas) { if ($l -match 'NAO PEGOU') { Aviso $l } else { Det $l } }

    foreach ($h in 'HKCU', 'HKLM') {
        $pol = (Get-ItemProperty "${h}:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
        if ($pol) { Aviso "a TI forca um fundo por politica ($h): $pol - ele pode voltar sozinho" }
        $trava = (Get-ItemProperty "${h}:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" -Name NoChangingWallPaper -ErrorAction SilentlyContinue).NoChangingWallPaper
        if ($trava) { Aviso "politica da TI bloqueia trocar o fundo ($h)" }
    }
    "$($linhas.Count) telas"
}

Passo 'Abrir' {
    Start-Process "$ahkDir\AutoHotkey64.exe" "`"$root\main.ahk`""
    Start-Process "$braveDir\brave.exe" $braveArgs
    Det 'AutoHotkey e Brave abertos'
}

# ---------------------------------------------------------------- resumo

$cor = if ($estado.falhas) { 'Red' } elseif ($estado.avisos) { 'Yellow' } else { 'Green' }
$resumo = '{0} ok   {1} aviso(s)   {2} falha(s)   em {3:N1} s' -f $estado.ok, $estado.avisos, $estado.falhas, $relogio.Elapsed.TotalSeconds
$largura = 62
Write-Host ''
Write-Host ('  +' + ('-' * $largura) + '+') -ForegroundColor DarkGray
Write-Host '  |  ' -ForegroundColor DarkGray -NoNewline
Write-Host $resumo.PadRight($largura - 2) -ForegroundColor $cor -NoNewline
Write-Host '|' -ForegroundColor DarkGray
Write-Host ('  +' + ('-' * $largura) + '+') -ForegroundColor DarkGray
Log "`n$resumo"

$atalhos = @(
    @('Win+Shift+B', 'abre o Brave'),
    @('Win+Shift+C', 'abre o Claude'),
    @('Win+Shift+T', 'janela sempre no topo'),
    @('Lateral mouse', 'segura / solta o clique esquerdo'),
    @('Win+Shift+L', 'limpa tudo e sai'),
    @('Win+Shift+Q', 'limpa tudo e desliga')
)
Write-Host ''
foreach ($a in $atalhos) {
    Write-Host ('    {0,-15}' -f $a[0]) -ForegroundColor Cyan -NoNewline
    Write-Host $a[1] -ForegroundColor DarkGray
}
Write-Host ''
if ($estado.falhas -or $estado.avisos) { Write-Host "  log completo: $($estado.log)" -ForegroundColor DarkGray; Write-Host '' }
}
