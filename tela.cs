// Papel de parede por monitor via IDesktopWallpaper. Usado pelo setup.ps1 e pelo cleanup.ps1.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

namespace SaunaTela {
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
        int GetPosition();
    }

    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")] public class DesktopWallpaper {}

    public static class Tela {
        static IDesktopWallpaper Novo() { return (IDesktopWallpaper)new DesktopWallpaper(); }

        // "id<TAB>caminho" de cada monitor conectado
        public static string[] Ler() {
            var w = Novo();
            var saida = new List<string>();
            for (uint i = 0; i < w.GetMonitorDevicePathCount(); i++) {
                string id = w.GetMonitorDevicePathAt(i);
                try { w.GetMonitorRECT(id); } catch { continue; }
                string atual = "";
                try { atual = w.GetWallpaper(id) ?? ""; } catch {}
                saida.Add(id + "\t" + atual);
            }
            return saida.ToArray();
        }

        public static int Posicao() { return Novo().GetPosition(); }
        public static uint Cor() { return Novo().GetBackgroundColor(); }

        public static string[] Aplicar(string principal, string demais) {
            var w = Novo();
            w.SetBackgroundColor(0);
            w.SetPosition(4);
            var saida = new List<string>();
            for (uint i = 0; i < w.GetMonitorDevicePathCount(); i++) {
                string id = w.GetMonitorDevicePathAt(i);
                Rect r;
                try { r = w.GetMonitorRECT(id); } catch { continue; }
                bool eh = r.Left == 0 && r.Top == 0;
                string alvo = eh ? principal : demais;
                w.SetWallpaper(id, alvo);
                string atual = "";
                try { atual = w.GetWallpaper(id) ?? ""; } catch {}
                string linha = string.Format("tela {0}: {1}x{2}{3} -> {4}", i + 1, r.Right - r.Left, r.Bottom - r.Top,
                    eh ? " (principal)" : "", Path.GetFileName(alvo));
                if (!string.Equals(Path.GetFileName(atual), Path.GetFileName(alvo), StringComparison.OrdinalIgnoreCase))
                    linha += "  NAO PEGOU, ficou: " + (atual == "" ? "(vazio)" : atual);
                saida.Add(linha);
            }
            return saida.ToArray();
        }

        // devolve quantos monitores foram restaurados
        public static int Restaurar(string[] ids, string[] caminhos, int posicao, uint cor) {
            var w = Novo();
            try { w.SetBackgroundColor(cor); } catch {}
            try { w.SetPosition(posicao); } catch {}
            int n = 0;
            for (int i = 0; i < ids.Length; i++) {
                try { w.SetWallpaper(ids[i], caminhos[i]); n++; } catch {}
            }
            return n;
        }
    }
}
