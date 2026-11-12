$ErrorActionPreference = 'SilentlyContinue'
$root    = "$env:LOCALAPPDATA\Ferramentas"
$snapDir = "$root\snapshot"
$snapArq = "$snapDir\snapshot.json"
$hist    = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
$rastro  = 'sauna-de-laudos|saunadelaudos|invertexto'

# 1. fecha tudo que roda de dentro da pasta (AHK, Brave)
for ($i = 0; $i -lt 20; $i++) {
    $p = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($root, 'OrdinalIgnoreCase') }
    if (-not $p) { break }
    $p | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

function Valor($v) {
    switch ($v.tipo) {
        'Binary'      { return [byte[]]@($v.valor) }
        'MultiString' { return [string[]]@($v.valor) }
        default       { return $v.valor }
    }
}

function Escrever([string]$chave, $v) {
    if (-not (Test-Path -LiteralPath $chave)) { New-Item $chave -Force | Out-Null }
    New-ItemProperty -LiteralPath $chave -Name $v.nome -Value (Valor $v) -PropertyType $v.tipo -Force | Out-Null
}

$snap = $null
if (Test-Path $snapArq) { $snap = [IO.File]::ReadAllText($snapArq) | ConvertFrom-Json }

if ($snap) {
    $inicio = if ($snap.inicio -is [datetime]) { $snap.inicio } else { [datetime]::Parse($snap.inicio, $null, 'RoundtripKind') }

    # 2. chaves inteiras (barra fixada, historico do Win+R)
    foreach ($c in @($snap.chaves)) {
        if (-not $c) { continue }
        if (-not $c.existia) { Remove-Item -LiteralPath $c.chave -Recurse -Force; continue }
        $k = Get-Item -LiteralPath $c.chave
        if ($k) { foreach ($n in $k.GetValueNames()) { if ($n) { Remove-ItemProperty -LiteralPath $c.chave -Name $n -Force } } }
        foreach ($v in @($c.valores)) { if ($v) { Escrever $c.chave $v } }
    }

    # tira do Win+R o que foi digitado pra chegar no script
    $mru = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    $k = Get-Item -LiteralPath $mru
    if ($k) {
        $lista = [string]$k.GetValue('MRUList')
        foreach ($n in $k.GetValueNames()) {
            if ($n.Length -eq 1 -and [string]$k.GetValue($n) -match $rastro) {
                Remove-ItemProperty -LiteralPath $mru -Name $n -Force
                $lista = $lista.Replace($n, '')
            }
        }
        Set-ItemProperty -LiteralPath $mru -Name MRUList -Value $lista
    }

    # 3. valores isolados
    foreach ($v in @($snap.valores)) {
        if (-not $v) { continue }
        if ($v.existia) { Escrever $v.chave $v }
        else { Remove-ItemProperty -LiteralPath $v.chave -Name $v.nome -Force }
    }

    # 4. chaves que o setup criou do zero
    foreach ($c in @($snap.criadas)) { if ($c) { Remove-Item -LiteralPath $c -Recurse -Force } }

    # 5. pastas (recentes, atalhos fixados) voltam exatamente ao que eram
    foreach ($p in @($snap.pastas)) {
        if (-not $p) { continue }
        if ($p.existia) { robocopy "$snapDir\$($p.id)" $p.pasta /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null }
        else { Remove-Item -LiteralPath $p.pasta -Recurse -Force }
    }

    # 6. arquivos (atalho do Brave)
    foreach ($a in @($snap.arquivos)) {
        if (-not $a) { continue }
        if ($a.existia) { Copy-Item -LiteralPath "$snapDir\$($a.id)" $a.arquivo -Force }
        else { Remove-Item -LiteralPath $a.arquivo -Force }
    }

    # 7. historico do PowerShell: volta ao tamanho de antes e sem as linhas do script
    if ((Test-Path $hist) -and $null -ne $snap.historico) {
        $linhas = @(Get-Content $hist | Select-Object -First ([int]$snap.historico) | Where-Object { $_ -notmatch $rastro })
        Set-Content $hist $linhas -Encoding UTF8
    }

    # 8. lixeira: so o que foi apagado depois do setup
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($inicio) { foreach ($d in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }) {
        foreach ($i in Get-ChildItem -LiteralPath "$($d.Name)`$Recycle.Bin\$sid" -Filter '$I*' -Force) {
            $b = [IO.File]::ReadAllBytes($i.FullName)
            if ($b.Length -lt 24) { continue }
            if ([datetime]::FromFileTime([BitConverter]::ToInt64($b, 16)) -ge $inicio) {
                Remove-Item -LiteralPath (Join-Path $i.DirectoryName ('$R' + $i.Name.Substring(2))) -Recurse -Force
                Remove-Item -LiteralPath $i.FullName -Force
            }
        }
    } }
} else {
    # sem snapshot (setup antigo): limpeza bruta
    Remove-Item -Recurse -Force -Path @(
        "$env:APPDATA\Microsoft\Windows\Recent\*"
        $hist
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Brave.lnk"
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
        'HKCU:\Software\Google\Chrome\Extensions\fcoeoabgfenejglbffodgkkbkcdhcgfn'
        'HKCU:\Software\Google\Chrome\Extensions\eimadpbcbfnmbkopoojfekhnkhdbieeh'
    )
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' SaunaDeLaudos
    Clear-RecycleBin -Force
}

# 9. area de transferencia (o Windows nao deixa apagar item por item)
try {
    $clip = [Windows.ApplicationModel.DataTransfer.Clipboard, Windows.ApplicationModel.DataTransfer, ContentType = WindowsRuntime]
    $clip::ClearHistory() | Out-Null
    $clip::Clear()
} catch {}

# 10. some com a pasta inteira (Brave, AHK, downloads, snapshot)
if ($env:LOCALAPPDATA -and (Split-Path $root) -eq $env:LOCALAPPDATA) {
    for ($i = 0; $i -lt 10 -and (Test-Path $root); $i++) {
        Remove-Item $root -Recurse -Force
        if (Test-Path $root) { Start-Sleep -Seconds 1 }
    }
}

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
