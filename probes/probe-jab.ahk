#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Probe 2 do editor do Agfa.
; O probe 1 mostrou javaw.exe / SunAwtFrame sem nenhum controle Win32: e Java (Swing),
; entao ControlGetText nunca vai enxergar o texto. O caminho e a Java Access Bridge (JAB).
;
;   F8  com o cursor DENTRO do texto do laudo -> diz se a JAB le o editor (so leitura)
;   F9  teste de escrita: digita " [teste]" no fim e apaga, conferindo pela JAB.
;       Use num laudo de teste/rascunho.
;
; Nada do texto do laudo aparece na tela: so tamanho e uma previa mascarada (xxxx 99).

global JAB := Map(), JABpronto := false
global Props := EnvGet("USERPROFILE") "\.accessibility.properties"

TrayTip "Clique dentro do texto do laudo no Agfa e aperte F8", "Probe JAB"

F8:: Probe()
F9:: TesteEscrita()

; ---------------------------------------------------------------- F8

Probe() {
    hwnd := WinExist("A")
    out := []
    caminho := WinGetProcessPath(hwnd)
    out.Push("Processo: " WinGetProcessName(hwnd) "   classe: " WinGetClass(hwnd))
    out.Push("Java: " caminho)
    try out.Push("Versao do javaw.exe: " FileGetVersion(caminho))
    out.Push("JVM 64 bits: " SimNao(Processo64(WinGetPID(hwnd))) "   |   AHK 64 bits: " SimNao(A_PtrSize = 8))

    SplitPath caminho, , &binJava
    dlls := ""
    Loop Files binJava "\*AccessBridge*.dll"
        dlls .= A_LoopFileName "  "
    out.Push("DLLs da bridge na pasta do Java: " (dlls || "NENHUMA"))
    out.Push("JAB ligada em " Props ": " SimNao(PropsLigada(Props)))
    for p in [binJava "\..\lib\accessibility.properties", binJava "\..\conf\accessibility.properties"]
        if PropsLigada(p)
            out.Push("JAB ligada pela instalacao do Java: " p)

    dll := AcharDll(binJava)
    out.Push("DLL usada: " (dll || "NAO ACHEI WindowsAccessBridge-" (A_PtrSize = 8 ? "64" : "32") ".dll"))
    if !dll
        return Mostrar(out)

    try {
        Iniciar(dll)
        java := false
        Loop 6 {
            if java := J("isJavaWindow", "Ptr", hwnd)
                break
            Sleep 500
        }
        out.Push("isJavaWindow: " SimNao(java))
        if !java {
            Mostrar(out)
            if !PropsLigada(Props)
                OferecerLigar()
            return
        }

        c := Contexto(hwnd)
        vi := Buffer(2048, 0)
        if J("getVersionInfo", "Int", c.vm, "Ptr", vi)
            out.Push("JVM: " StrGet(vi, 256, "UTF-16") "   bridge: " StrGet(vi.Ptr + 1536, 256, "UTF-16"))

        info := Buffer(6400, 0)
        J("getAccessibleContextInfo", "Int", c.vm, "Int64", c.ac, "Ptr", info)
        out.Push("")
        out.Push("Componente com foco:")
        out.Push("  papel:   " StrGet(info.Ptr + 4608, 256, "UTF-16"))
        out.Push("  estados: " StrGet(info.Ptr + 5632, 256, "UTF-16"))
        out.Push("  tamanho: " NumGet(info, 6160, "Int") " x " NumGet(info, 6164, "Int") "   filhos: " NumGet(info, 6148, "Int"))
        out.Push("  tem AccessibleText: " SimNao(NumGet(info, 6180, "Int")))

        if NumGet(info, 6180, "Int") {
            t := LerTudo(c)
            out.Push("  caracteres: " t.n "   cursor em: " t.caret "   lidos: " StrLen(t.texto))
            previa := RegExReplace(RegExReplace(SubStr(t.texto, 1, 60), "\pL", "x"), "\d", "9")
            out.Push("  previa mascarada: " StrReplace(StrReplace(previa, "`r", ""), "`n", "|"))
        }
        out.Push("")
        out.Push("Funcoes de escrita na DLL:")
        for f in ["setCaretPosition", "selectTextRange", "setTextContents"]
            out.Push("  " f ": " SimNao(JAB[f]))
        J("releaseJavaObject", "Int", c.vm, "Int64", c.ac)
    } catch as e {
        out.Push("ERRO: " e.Message)
    }
    Mostrar(out)
}

; ---------------------------------------------------------------- F9

TesteEscrita() {
    hwnd := WinExist("A")
    if MsgBox("Teste de escrita: vou digitar ' [teste]' no FIM do texto e apagar em seguida, conferindo tudo pela bridge.`n`nUse num laudo de teste ou rascunho. Continuar?", "Probe JAB", "YesNo Icon! Default2") != "Yes"
        return
    WinActivate hwnd
    WinWaitActive hwnd, , 2
    Sleep 300
    r := []
    try {
        if !JABpronto
            throw Error("aperte F8 primeiro")
        c := Contexto(hwnd)
        antes := LerTudo(c)
        r.Push("antes: " antes.n " caracteres, cursor em " antes.caret)

        ok := J("setCaretPosition", "Int", c.vm, "Int64", c.ac, "Int", antes.n)
        Sleep 150
        r.Push("setCaretPosition(fim): " ok " -> cursor agora em " TextoInfo(c).caret)

        marca := " [teste]"
        SendText marca
        Sleep 400
        meio := LerTudo(c)
        r.Push("depois de digitar: " meio.n " caracteres; termina com a marca: " SimNao(SubStr(meio.texto, -StrLen(marca)) == marca))

        ok := J("selectTextRange", "Int", c.vm, "Int64", c.ac, "Int", antes.n, "Int", antes.n + StrLen(marca))
        Sleep 150
        r.Push("selectTextRange(marca): " ok)
        Send "{Delete}"
        Sleep 400
        depois := LerTudo(c)
        igual := depois.texto == antes.texto
        r.Push("texto final identico ao original: " (igual ? "SIM" : "NAO - confira o fim do laudo e apague a marca na mao"))

        J("setCaretPosition", "Int", c.vm, "Int64", c.ac, "Int", antes.caret)
        J("releaseJavaObject", "Int", c.vm, "Int64", c.ac)
    } catch as e {
        r.Push("ERRO: " e.Message)
    }
    Mostrar(r)
}

; ---------------------------------------------------------------- JAB

Iniciar(dll) {
    global JABpronto
    if JABpronto
        return
    h := DllCall("LoadLibraryEx", "Str", dll, "Ptr", 0, "UInt", 0x8, "Ptr")   ; LOAD_WITH_ALTERED_SEARCH_PATH
    if !h
        throw Error("nao carregou " dll " (erro " A_LastError ")")
    for f in ["Windows_run", "isJavaWindow", "getAccessibleContextWithFocus", "getAccessibleContextInfo", "getAccessibleTextInfo",
              "getAccessibleTextRange", "getVersionInfo", "releaseJavaObject", "setCaretPosition", "selectTextRange", "setTextContents"]
        JAB[f] := DllCall("GetProcAddress", "Ptr", h, "AStr", f, "Ptr")
    J("Windows_run")
    Sleep 1000   ; a bridge acha as JVMs por mensagens de janela; o Sleep deixa elas chegarem
    JABpronto := true
}

J(f, args*) {
    if !JAB.Get(f, 0)
        throw Error("a DLL nao tem " f)
    a := args.Clone()
    a.Push("Cdecl Int")
    return DllCall(JAB[f], a*)
}

Contexto(hwnd) {
    if !J("isJavaWindow", "Ptr", hwnd)
        throw Error("isJavaWindow = 0 (a bridge nao enxerga essa janela)")
    vm := 0, ac := 0
    if !J("getAccessibleContextWithFocus", "Ptr", hwnd, "Int*", &vm, "Int64*", &ac)
        throw Error("getAccessibleContextWithFocus falhou")
    return {vm: vm, ac: ac}
}

TextoInfo(c) {
    ti := Buffer(12, 0)
    if !J("getAccessibleTextInfo", "Int", c.vm, "Int64", c.ac, "Ptr", ti, "Int", 0, "Int", 0)
        throw Error("getAccessibleTextInfo falhou")
    return {n: NumGet(ti, 0, "Int"), caret: NumGet(ti, 4, "Int")}
}

; getAccessibleTextRange tem fim inclusivo e no maximo ~10k caracteres por chamada
LerTudo(c) {
    i := TextoInfo(c), s := "", ini := 0
    while ini < i.n {
        fim := Min(ini + 8000, i.n) - 1
        tam := fim - ini + 2
        buf := Buffer(tam * 2, 0)
        if !J("getAccessibleTextRange", "Int", c.vm, "Int64", c.ac, "Int", ini, "Int", fim, "Ptr", buf, "Short", tam)
            throw Error("getAccessibleTextRange falhou em " ini "-" fim)
        s .= StrGet(buf, tam - 1, "UTF-16")
        ini := fim + 1
    }
    return {texto: s, n: i.n, caret: i.caret}
}

; ---------------------------------------------------------------- utilidades

AcharDll(binJava) {
    nome := "WindowsAccessBridge-" (A_PtrSize = 8 ? "64" : "32") ".dll"
    for d in [binJava, A_WinDir "\System32", A_WinDir "\SysWOW64"]
        if FileExist(d "\" nome)
            return d "\" nome
    return ""
}

PropsLigada(arq) {
    try return FileExist(arq) && InStr(FileRead(arq), "com.sun.java.accessibility.AccessBridge")
    return false
}

OferecerLigar() {
    msg := "A Java Access Bridge esta desligada para este usuario.`n`nLigar agora? So cria/edita o arquivo`n" Props
         . "`n(sem admin; pra desfazer e so apagar o arquivo).`n`nDepois FECHE e ABRA o Agfa e aperte F8 de novo."
    if MsgBox(msg, "Probe JAB", "YesNo Icon?") != "Yes"
        return
    FileAppend "`nassistive_technologies=com.sun.java.accessibility.AccessBridge`nscreen_magnifier_present=true`n", Props, "UTF-8-RAW"
    MsgBox "Pronto. Agora feche e abra o Agfa.", "Probe JAB"
}

Processo64(pid) {
    if !A_Is64bitOS
        return false
    h := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
    if !h
        return "?"
    wow := 0
    DllCall("IsWow64Process", "Ptr", h, "Int*", &wow)
    DllCall("CloseHandle", "Ptr", h)
    return !wow
}

SimNao(v) => v == "?" ? "?" : (v ? "sim" : "NAO")

Mostrar(linhas) {
    txt := ""
    for l in linhas
        txt .= l "`r`n"
    g := Gui("+AlwaysOnTop", "Probe JAB - manda um print disto")
    g.SetFont("s10", "Consolas")
    g.Add("Edit", "ReadOnly -Wrap w760 r" Min(linhas.Length + 1, 32), txt)
    g.Add("Button", "Default w80", "OK").OnEvent("Click", (*) => g.Destroy())
    g.Show()
}
