#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Ctrl+Z / Ctrl+Shift+Z no editor de laudos do Agfa (IMPAX Agility).
; O editor e Swing: o texto e lido e editado pela Java Access Bridge.

global Jab := Map(), JabEstado := 0, Campos := [], JanelasAgfa := Map()

PAUSA     := 1000    ; ms sem mudanca para fechar um passo
TECLADO   := 2000    ; texto que muda sem tecla nesse intervalo veio de fora (outro laudo, ditado)
MAXPASSOS := 300

if A_PtrSize != 8 {
    MsgBox "Abra com o AutoHotkey64.exe: o Java do Agfa e 64 bits.", "Desfazer"
    ExitApp
}
A_IconTip := "Desfazer no Agfa (Ctrl+Z / Ctrl+Shift+Z)"
LigarBridge()
InstallKeybdHook
SetTimer DzVigiar, 400

#HotIf AgfaAtivo()
$^z:: DzPasso(-1, "^z")
$^+z:: DzPasso(1, "^+z")
#HotIf

; a bridge so funciona com ela ligada no perfil do usuario antes do Agfa abrir
LigarBridge() {
    arq := EnvGet("USERPROFILE") "\.accessibility.properties"
    try if RegExMatch(FileRead(arq), "m)^[ \t]*assistive_technologies[ \t]*=.*AccessBridge")
        return
    if MsgBox("Para o Ctrl+Z funcionar no Agfa, a Java Access Bridge precisa estar ligada para o seu usuário.`n`n"
            . "Isso só acrescenta uma linha em`n" arq "`n(sem admin; para desfazer, apague a linha).`n`nLigar agora?",
            "Desfazer", "YesNo Icon? 262144") != "Yes"
        ExitApp
    FileAppend "`nassistive_technologies=com.sun.java.accessibility.AccessBridge`nscreen_magnifier_present=true`n", arq, "UTF-8-RAW"
    if WinExist("ahk_exe javaw.exe")
        MsgBox "Ligada. Feche e abra o Agfa para valer.", "Desfazer", 262144
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
    Critical
    if !(hwnd := AgfaAtivo())
        return
    try {
        c := CampoAtual(hwnd)
        if IsObject(c)
            Observar(c)
    }
}

Observar(c) {
    i := TextoInfo(c)
    c.ciclo++
    if i.n != c.n || !Mod(c.ciclo, 3) || !c.hist.Length {
        t := LerTexto(c, i.n)
        c.n := i.n
        if t !== c.visto {
            if c.hist.Length && A_TimeIdleKeyboard > TECLADO
                c.externo := true
            c.visto := t, c.mudou := A_TickCount
        }
    }
    if !c.hist.Length
        Zerar(c)
    else if c.visto !== c.hist[c.idx] && A_TickCount - c.mudou >= PAUSA
        Registrar(c)
}

Zerar(c) {
    c.hist := [c.visto], c.idx := 1, c.externo := false
}

Registrar(c) {
    if c.externo || Trocou(c.hist[c.idx], c.visto)
        return Zerar(c)
    while c.hist.Length > c.idx
        c.hist.Pop()
    c.hist.Push(c.visto)
    if c.hist.Length > MAXPASSOS
        c.hist.RemoveAt(1)
    c.idx := c.hist.Length
}

; outro laudo no mesmo campo: texto grande surgindo num campo vazio, ou quase nada em comum
Trocou(a, b) {
    la := StrLen(Trim(a, " `t`r`n")), lb := StrLen(Trim(b, " `t`r`n"))
    if la < 10
        return lb >= 50
    if la < 50 || lb < 50
        return false
    d := Diff(a, b)
    return d.p + d.s < 0.2 * Max(StrLen(a), StrLen(b))
}

DzPasso(dir, tecla) {
    Critical
    c := ""
    try c := CampoAtual(AgfaAtivo())
    if !IsObject(c) {
        Send tecla
        return
    }
    try {
        t := LerTudo(c)
        if t !== c.visto
            c.visto := t, c.n := StrLen(t), c.mudou := A_TickCount
        if !c.hist.Length
            Zerar(c)
        else if c.visto !== c.hist[c.idx]
            Registrar(c)

        alvoIdx := c.idx + dir
        if alvoIdx < 1 || alvoIdx > c.hist.Length
            return Dica(dir < 0 ? "Nada para desfazer" : "Nada para refazer")
        ok := Aplicar(c, c.hist[alvoIdx])
        c.visto := LerTudo(c), c.n := StrLen(c.visto), c.mudou := A_TickCount
        if ok {
            c.idx := alvoIdx
            Dica((dir < 0 ? "Desfeito " : "Refeito ") c.idx "/" c.hist.Length)
        } else
            Dica("O texto não voltou exatamente como era. Confira.", 4000)
    } catch as e
        Dica("Desfazer falhou: " e.Message, 4000)
}

; troca so o trecho que difere; confere a selecao antes e o texto depois, com uma nova tentativa
Aplicar(c, alvo) {
    clip := ""
    try {
        Loop 2 {
            t := LerTudo(c)
            if t == alvo
                return true
            d := Diff(t, alvo)
            tira := StrLen(t) - d.p - d.s
            poe := SubStr(alvo, d.p + 1, StrLen(alvo) - d.p - d.s)
            if !Posicionar(c, d.p, tira)
                continue
            if poe == ""
                Send "{Delete}"
            else {
                if !IsObject(clip)
                    clip := ClipboardAll()
                Copiar(poe)
                Send "^v"
            }
            Loop 15 {
                Sleep 80
                if LerTudo(c) == alvo
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
    Loop 2 {
        if n
            JabCall("selectTextRange", "Int", c.vm, "Int64", c.ac, "Int", p, "Int", p + n)
        else
            JabCall("setCaretPosition", "Int", c.vm, "Int64", c.ac, "Int", p)
        Sleep 40
        b := Buffer(2056, 0)
        if JabCall("getAccessibleTextSelectionInfo", "Int", c.vm, "Int64", c.ac, "Ptr", b)
            && NumGet(b, 0, "Int") = p && NumGet(b, 4, "Int") = p + n
            return true
    }
    return false
}

; prefixo e sufixo em comum, por busca binaria
Diff(a, b) {
    la := StrLen(a), lb := StrLen(b), m := Min(la, lb)
    lo := 0, hi := m
    while lo < hi {
        k := (lo + hi + 1) // 2
        if SubStr(a, 1, k) == SubStr(b, 1, k)
            lo := k
        else
            hi := k - 1
    }
    p := lo, lo := 0, hi := m - p
    while lo < hi {
        k := (lo + hi + 1) // 2
        if SubStr(a, la - k + 1) == SubStr(b, lb - k + 1)
            lo := k
        else
            hi := k - 1
    }
    return {p: p, s: lo}
}

CampoAtual(hwnd) {
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
            return c
        }
    info := Buffer(6200, 0)
    if !JabCall("getAccessibleContextInfo", "Int", vm, "Int64", ac, "Ptr", info)
        || !NumGet(info, 6180, "Int")
        || !InStr(StrGet(info.Ptr + 5632, 256, "UTF-16"), "editable") {
        Soltar(vm, ac)
        return ""
    }
    c := {vm: vm, ac: ac, hist: [], idx: 0, n: -1, ciclo: 0, visto: "", mudou: 0, externo: false}
    Campos.InsertAt(1, c)
    while Campos.Length > 6 {
        v := Campos.Pop()
        Soltar(v.vm, v.ac)
    }
    return c
}

CarregarJab(hwnd) {
    global JabEstado
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
            return ""
        }
    }
    JabCall("Windows_run")
    JabEstado := 1
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

; o fim do intervalo e inclusivo e cada chamada devolve no maximo ~10 mil caracteres
LerTexto(c, n) {
    s := "", ini := 0
    while ini < n {
        fim := Min(ini + 8000, n) - 1
        tam := fim - ini + 2
        b := Buffer(tam * 2, 0)
        if !JabCall("getAccessibleTextRange", "Int", c.vm, "Int64", c.ac, "Int", ini, "Int", fim, "Ptr", b, "Short", tam)
            throw Error("leitura do texto falhou")
        s .= StrGet(b, tam - 1, "UTF-16")
        ini := fim + 1
    }
    return s
}

LerTudo(c) => LerTexto(c, TextoInfo(c).n)

; texto marcado para ficar fora do historico do Win+V
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
