#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Ctrl+Z / Ctrl+Shift+Z no editor de laudos do Agfa (IMPAX Agility), via Java Access Bridge.

global Jab := Map(), JabEstado := 0, JabDesde := 0, Campos := [], JanelasAgfa := Map(), UltimoColar := 0, UltimoCampo := "", Ignorado := "", Intervalo := 250

PALAVRAS  := 1       ; palavras digitadas por passo de desfazer
PAUSA     := 1000    ; ms sem mudanca para fechar um passo
TECLADO   := 2000    ; ms sem tecla para uma mudanca contar como externa
MAXPASSOS := 1000
JANELA    := 200     ; caracteres lidos de cada lado do cursor
CONFERE   := 30000   ; ms entre leituras completas com o texto parado
SEPARA    := "\s.,;:!?()"   ; o que termina uma palavra

if A_PtrSize != 8 {
    MsgBox "Abra com o AutoHotkey64.exe: o Java do Agfa e 64 bits.", "Desfazer"
    ExitApp
}
A_IconTip := "Desfazer no Agfa: Ctrl+Z desfaz, Ctrl+Shift+Z refaz"
LigarBridge()
InstallKeybdHook
SetTimer DzVigiar, 250

#MaxThreadsBuffer True
#HotIf AgfaAtivo()
$^z:: DzPasso(-1, "^z")
$^+z:: DzPasso(1, "^+z")
~^v::
~+Ins:: {
    global UltimoColar := A_TickCount
}
#HotIf

LigarBridge() {
    arq := EnvGet("USERPROFILE") "\.accessibility.properties"
    try if RegExMatch(FileRead(arq), "m)^[ \t]*assistive_technologies[ \t]*=.*AccessBridge")
        return
    if MsgBox("Para o Ctrl+Z funcionar no Agfa, é necessário ligar um recurso de acessibilidade do seu usuário.`n`n"
            . "Vale só para seu usuário do Windows e não muda nada no Agfa.`n`nLigar agora?",
            "Desfazer no Agfa", "YesNo Icon? 262144") != "Yes"
        ExitApp
    FileAppend "`nassistive_technologies=com.sun.java.accessibility.AccessBridge`nscreen_magnifier_present=true`n", arq, "UTF-8-RAW"
    if WinExist("ahk_exe javaw.exe")
        MsgBox "Pronto. Agora reinicie o Agfa.", "Desfazer no Agfa", 262144
}

AgfaAtivo() {
    if JabEstado < 0 || !(hwnd := WinActive("ahk_exe javaw.exe"))
        return 0
    if !JanelasAgfa.Has(hwnd) {
        if JanelasAgfa.Count > 50
            JanelasAgfa.Clear()
        try JanelasAgfa[hwnd] := InStr(WinGetProcessPath(hwnd), "\AGFA\") > 0
        catch
            return 0
    }
    return JanelasAgfa[hwnd] ? hwnd : 0
}

DzVigiar() {
    global UltimoCampo, Intervalo
    Critical
    c := ""
    if hwnd := AgfaAtivo() {
        try c := CampoAtual(hwnd)
        if IsObject(c)
            try Observar(c, c !== UltimoCampo)
    }
    UltimoCampo := c
    if Intervalo != (t := A_TimeIdlePhysical < 1500 ? 250 : 1000)
        SetTimer DzVigiar, Intervalo := t
}

Observar(c, voltou) {
    i := TextoInfo(c), agora := A_TickCount
    if !c.iniciado || voltou || A_TimeIdleKeyboard >= PAUSA && (c.mudou > c.conferido || agora - c.conferido >= CONFERE)
        LerCompleto(c, i, voltou ? 2 : 1)
    else if i.n != c.n || i.caret != c.caret || A_TimeIdleKeyboard < 1000
        LerPerto(c, i)
    if c.pend && agora - c.mudou >= PAUSA
        Registrar(c)
}

LerCompleto(c, i, modo) {
    t := LerTexto(c, 0, i.n)
    if c.iniciado
        Ver(c, t, i.caret, modo)
    else
        Iniciar(c, t, i.caret)
    c.conferido := A_TickCount
}

LerPerto(c, i) {
    delta := i.n - c.n
    lo := Max(0, i.caret - JANELA), hi := Min(i.n, i.caret + JANELA), hiV := hi - delta
    if hiV < lo || hiV > c.n
        return LerCompleto(c, i, 1)
    novo := LerTexto(c, lo, hi), velho := SubStr(c.visto, lo + 1, hiV - lo)
    if novo == velho {
        if delta
            return LerCompleto(c, i, 1)
        c.caret := i.caret
        return
    }
    d := Diff(velho, novo)
    if !d.p && lo || !d.s && hi < i.n
        return LerCompleto(c, i, 1)
    Ver(c, SubStr(c.visto, 1, lo) novo SubStr(c.visto, hiV + 1), i.caret, 1,
        {p: lo + d.p, tira: StrLen(velho) - d.p - d.s, poe: StrLen(novo) - d.p - d.s})
}

Iniciar(c, t, caret) {
    c.visto := t, c.n := StrLen(t), c.caret := caret, c.iniciado := true
    Zerar(c)
}

Zerar(c) {
    c.hist := [], c.idx := 0, c.base := c.visto, c.pend := "", c.externo := c.bloco := c.colou := false
}

; modo: 0 Ctrl+Z, 1 leitura, 2 texto mudou enquanto o campo estava sem foco
Ver(c, t, caret, modo, mud := "") {
    c.caret := caret
    if !IsObject(mud) {
        if t == c.visto
            return
        d := Diff(c.visto, t)
        mud := {p: d.p, tira: StrLen(c.visto) - d.p - d.s, poe: StrLen(t) - d.p - d.s}
    }
    p := mud.p, tira := mud.tira, poe := mud.poe
    colou := A_TickCount - UltimoColar <= TECLADO
    if modo = 2
        ext := true
    else if colou
        ext := false
    else if modo = 1 && A_TimeIdleKeyboard > TECLADO
        ext := true
    else
        ext := tira && poe && (tira >= 10 && poe >= 10 || caret < p - 3 || caret > p + poe + 3)
    bloco := !ext && (colou || poe >= 8 || tira >= 10 || tira >= 2 && poe >= 1)

    if c.pend && (ext != c.externo || bloco || c.bloco || !Continua(c.pend, p, tira, poe))
        Registrar(c)
    if c.pend
        c.pend := {ini: Min(c.pend.ini, p), fim: Max(c.pend.fim, p + tira) + poe - tira, saldo: c.pend.saldo + poe - tira}
    else
        c.pend := {ini: p, fim: p + poe, saldo: poe - tira}
    c.visto := t, c.n := StrLen(t), c.mudou := A_TickCount, c.externo := ext, c.bloco := bloco, c.colou := colou
    if bloco
        Registrar(c)
}

Continua(r, p, tira, poe) => (r.saldo >= 0) == (poe >= tira) && p <= r.fim && p + tira >= r.ini

Registrar(c) {
    r := c.pend, ext := c.externo, bloco := c.bloco, colou := c.colou
    velho := SubStr(c.base, r.ini + 1, r.fim - r.saldo - r.ini)
    novo := SubStr(c.visto, r.ini + 1, r.fim - r.ini)
    d := Diff(velho, novo)
    p := r.ini + d.p
    velho := SubStr(velho, d.p + 1, StrLen(velho) - d.p - d.s)
    novo := SubStr(novo, d.p + 1, StrLen(novo) - d.p - d.s)
    c.pend := "", c.externo := c.bloco := c.colou := false
    if velho == "" && novo == ""
        return c.base := c.visto
    if !colou && Trocou(c.base, c.visto, velho) || ext && velho != ""
        return Zerar(c)
    while c.hist.Length > c.idx
        c.hist.Pop()
    if ext || bloco || velho != ""
        c.hist.Push({p: p, velho: velho, novo: novo})
    else
        for e in Etapas(p, novo)
            c.hist.Push(e)
    if c.hist.Length > MAXPASSOS
        c.hist.RemoveAt(1, c.hist.Length - MAXPASSOS)
    c.idx := c.hist.Length, c.base := c.visto
}

Etapas(p, novo) {
    etapas := [], ini := 0, pos := 1, n := 0
    while RegExMatch(novo, "[^" SEPARA "][" SEPARA "]+", &m, pos) {
        pos := m.Pos + m.Len
        if ++n >= PALAVRAS && pos <= StrLen(novo) {
            etapas.Push({p: p + ini, velho: "", novo: SubStr(novo, ini + 1, pos - 1 - ini)})
            ini := pos - 1, n := 0
        }
    }
    etapas.Push({p: p + ini, velho: "", novo: SubStr(novo, ini + 1)})
    return etapas
}

Trocou(a, b, velho) {
    la := StrLen(Trim(a, " `t`r`n")), lb := StrLen(Trim(b, " `t`r`n"))
    if la < 10
        return lb >= 50
    if la < 50 || lb < 50
        return false
    return StrLen(a) - StrLen(velho) < 0.2 * Max(StrLen(a), StrLen(b))
}

DzPasso(dir, tecla) {
    global UltimoCampo
    Critical
    hwnd := AgfaAtivo(), c := ""
    try c := CampoAtual(hwnd)
    if !IsObject(c) {
        Send tecla
        if hwnd && JabEstado = 1 && A_TickCount - JabDesde > 3000 && !JabCall("isJavaWindow", "Ptr", hwnd)
            Dica("O Ctrl+Z vai funcionar depois que você reiniciar o Agfa.", 4000)
        return
    }
    voltou := c !== UltimoCampo, UltimoCampo := c
    try {
        i := TextoInfo(c)
        if !c.iniciado || voltou || i.n != c.n || A_TickCount - c.desfeito > 1000 {
            t := LerTexto(c, 0, i.n)
            if c.iniciado
                Ver(c, t, i.caret, voltou ? 2 : 0)
            else
                Iniciar(c, t, i.caret)
            c.conferido := A_TickCount
        }
        if c.pend
            Registrar(c)

        k := dir < 0 ? c.idx : c.idx + 1
        if k < 1 || k > c.hist.Length
            return
        passo := c.hist[k]
        de := dir < 0 ? passo.novo : passo.velho, para := dir < 0 ? passo.velho : passo.novo
        if SubStr(c.visto, passo.p + 1, StrLen(de)) !== de || LerTexto(c, passo.p, passo.p + StrLen(de)) !== de
            return Zerar(c)
        esperado := SubStr(c.visto, 1, passo.p) para SubStr(c.visto, passo.p + StrLen(de) + 1)

        ok := Aplicar(c, passo.p, StrLen(de), para, esperado)
        if ok
            c.idx := dir < 0 ? k - 1 : k, c.desfeito := A_TickCount
        i := TextoInfo(c)
        c.visto := ok ? esperado : LerTexto(c, 0, i.n)
        c.base := c.visto, c.n := StrLen(c.visto), c.caret := i.caret, c.pend := ""
        c.mudou := c.conferido := A_TickCount
        if !ok
            Dica("O texto não voltou exatamente como era. Confira.", 4000)
    } catch as erro
        Dica("Desfazer falhou: " erro.Message, 4000)
}

Aplicar(c, p, n, poe, esperado) {
    clip := ""
    try {
        Loop 2 {
            if A_Index > 1 {
                real := LerTexto(c, 0, TextoInfo(c).n)
                if real == esperado
                    return true
                d := Diff(real, esperado)
                p := d.p, n := StrLen(real) - d.p - d.s
                poe := SubStr(esperado, d.p + 1, StrLen(esperado) - d.p - d.s)
            }
            if !Posicionar(c, p, n)
                continue
            if poe == ""
                Send "{Delete}"
            else {
                if !IsObject(clip)
                    clip := ClipboardAll()
                Copiar(poe)
                Send "^v"
            }
            a := Max(0, p - 20), b := Min(StrLen(esperado), p + StrLen(poe) + 20)
            trecho := SubStr(esperado, a + 1, b - a)
            Loop 80 {
                Sleep 15
                if TextoInfo(c).n = StrLen(esperado) && LerTexto(c, a, b) == trecho
                    return true
            }
        }
        return false
    } finally {
        if IsObject(clip)
            A_Clipboard := clip
    }
}

Posicionar(c, p, n) {
    if n
        JabCall("selectTextRange", "Int", c.vm, "Int64", c.ac, "Int", p, "Int", p + n)
    else
        JabCall("setCaretPosition", "Int", c.vm, "Int64", c.ac, "Int", p)
    b := Buffer(2056, 0)
    Loop 10 {
        if JabCall("getAccessibleTextSelectionInfo", "Int", c.vm, "Int64", c.ac, "Ptr", b)
            && NumGet(b, 0, "Int") = p && NumGet(b, 4, "Int") = p + n
            return true
        Sleep 10
    }
    return false
}

Diff(a, b) {
    la := StrLen(a), lb := StrLen(b), m := Min(la, lb), pa := StrPtr(a), pb := StrPtr(b)
    p := DllCall("ntdll\RtlCompareMemory", "Ptr", pa, "Ptr", pb, "UPtr", m * 2, "UPtr") // 2
    lo := 0, hi := m - p
    while lo < hi {
        k := (lo + hi + 1) // 2
        if DllCall("msvcrt\memcmp", "Ptr", pa + (la - k) * 2, "Ptr", pb + (lb - k) * 2, "UPtr", k * 2, "Int")
            hi := k - 1
        else
            lo := k
    }
    return {p: p, s: lo}
}

CampoAtual(hwnd) {
    global Ignorado
    if JabEstado = 0
        return CarregarJab(hwnd)
    if !JabCall("isJavaWindow", "Ptr", hwnd)
        return ""
    vm := 0, ac := 0
    if !JabCall("getAccessibleContextWithFocus", "Ptr", hwnd, "Int*", &vm, "Int64*", &ac) || !ac
        return ""
    for c in Campos
        if c.vm = vm && JabCall("isSameObject", "Int", vm, "Int64", ac, "Int64", c.ac) {
            Soltar(vm, ac)
            if A_Index > 1
                Campos.InsertAt(1, Campos.RemoveAt(A_Index))
            return c
        }
    if Ignorado && Ignorado.vm = vm && JabCall("isSameObject", "Int", vm, "Int64", ac, "Int64", Ignorado.ac) {
        Soltar(vm, ac)
        return ""
    }
    info := Buffer(6200, 0)
    if !JabCall("getAccessibleContextInfo", "Int", vm, "Int64", ac, "Ptr", info)
        || !NumGet(info, 6180, "Int")
        || !InStr(StrGet(info.Ptr + 5632, 256, "UTF-16"), "editable")
        || InStr(StrGet(info.Ptr + 4608, 256, "UTF-16"), "password") {
        if Ignorado
            Soltar(Ignorado.vm, Ignorado.ac)
        Ignorado := {vm: vm, ac: ac}
        return ""
    }
    c := {vm: vm, ac: ac, iniciado: false, visto: "", base: "", n: 0, caret: 0, hist: [], idx: 0, pend: "",
          mudou: 0, conferido: 0, desfeito: 0, externo: false, bloco: false, colou: false}
    Campos.InsertAt(1, c)
    while Campos.Length > 6 {
        v := Campos.Pop()
        Soltar(v.vm, v.ac)
    }
    return c
}

CarregarJab(hwnd) {
    global JabEstado, JabDesde
    SplitPath WinGetProcessPath(hwnd), , &bin
    h := 0
    for dll in [bin "\WindowsAccessBridge-64.dll", A_WinDir "\System32\WindowsAccessBridge-64.dll"]
        if FileExist(dll) && (h := DllCall("LoadLibraryEx", "Str", dll, "Ptr", 0, "UInt", 8, "Ptr"))
            break
    for f in ["Windows_run", "isJavaWindow", "getAccessibleContextWithFocus", "getAccessibleContextInfo",
              "isSameObject", "releaseJavaObject", "getAccessibleTextInfo", "getAccessibleTextRange",
              "getAccessibleTextSelectionInfo", "selectTextRange", "setCaretPosition"] {
        Jab[f] := h ? DllCall("GetProcAddress", "Ptr", h, "AStr", f, "Ptr") : 0
        if !Jab[f] {
            JabEstado := -1
            SetTimer DzVigiar, 0
            MsgBox "Não encontrei no Agfa o recurso que o Ctrl+Z usa. Ele vai ficar desligado neste PC.", "Desfazer no Agfa", 262144
            return ""
        }
    }
    JabCall("Windows_run")
    JabEstado := 1, JabDesde := A_TickCount
    return ""
}

JabCall(f, args*) {
    args.Push("Cdecl Int")
    return DllCall(Jab[f], args*)
}

Soltar(vm, obj) => JabCall("releaseJavaObject", "Int", vm, "Int64", obj)

TextoInfo(c) {
    b := Buffer(12, 0)
    if !JabCall("getAccessibleTextInfo", "Int", c.vm, "Int64", c.ac, "Ptr", b, "Int", 0, "Int", 0)
        throw Error("sem acesso ao texto")
    return {n: NumGet(b, 0, "Int"), caret: NumGet(b, 4, "Int")}
}

LerTexto(c, ini, fim) {
    s := ""
    while ini < fim {
        ate := Min(ini + 8000, fim) - 1
        tam := ate - ini + 2
        b := Buffer(tam * 2, 0)
        if !JabCall("getAccessibleTextRange", "Int", c.vm, "Int64", c.ac, "Int", ini, "Int", ate, "Ptr", b, "Short", tam)
            throw Error("leitura do texto falhou")
        s .= StrGet(b, tam - 1, "UTF-16")
        ini := ate + 1
    }
    return s
}

Copiar(t) {
    t := StrReplace(t, "`n", "`r`n")
    Loop 10 {
        if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
            break
        if A_Index = 10 {
            A_Clipboard := t
            return
        }
        Sleep 20
    }
    DllCall("EmptyClipboard")
    h := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", (StrLen(t) + 1) * 2, "Ptr")
    StrPut(t, DllCall("GlobalLock", "Ptr", h, "Ptr"), "UTF-16")
    DllCall("GlobalUnlock", "Ptr", h)
    DllCall("SetClipboardData", "UInt", 13, "Ptr", h)
    for nome in ["ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"]
        DllCall("SetClipboardData", "UInt", DllCall("RegisterClipboardFormat", "Str", nome, "UInt"),
                "Ptr", DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", 4, "Ptr"))
    DllCall("CloseClipboard")
}

Dica(msg, ms := 1000) {
    ToolTip msg, , , 19
    SetTimer () => ToolTip(, , , 19), -ms
}
