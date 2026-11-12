#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

Brave := A_ScriptDir "\Brave\brave.exe"
BraveArgs := '--user-data-dir="' A_ScriptDir '\BraveData" --no-first-run --no-default-browser-check --disable-features=AIChat,BraveVPN,BraveRewards,MediaRouter'

AbrirBrave(extra := "") => Run('"' Brave '" ' BraveArgs ' ' extra)

#+b:: WinExist("ahk_exe brave.exe") ? WinActivate() : AbrirBrave()
#+c:: AbrirBrave("--app=https://claude.ai")
#+t:: WinSetAlwaysOnTop(-1, "A")
XButton2:: Send(GetKeyState("LButton") ? "{LButton up}" : "{LButton down}")

#+l::
^!+l:: Sair("logout")

#+q::
^!+q:: Sair("desligar")

Sair(modo) {
    if MsgBox(modo = "desligar" ? "Limpar tudo e desligar?" : "Limpar tudo e sair?", "Sauna de Laudos", "YesNo Icon? Default2") != "Yes"
        return
    ps := A_ScriptDir "\cleanup.ps1"
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$modo=' "'" modo "'" '; iex ([IO.File]::ReadAllText(' "'" ps "'" '))"', , "Hide")
    ExitApp()
}

OnExit((*) => GetKeyState("LButton") ? Send("{LButton up}") : 0)
