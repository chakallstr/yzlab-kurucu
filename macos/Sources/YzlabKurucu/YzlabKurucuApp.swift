import SwiftUI

// @main YOK: giris noktasi main.swift (komut satiri modlari icin). Pencere modu
// oradan `YzlabKurucuApp.main()` ile acilir.
struct YzlabKurucuApp: App {
    @State private var manifest: Manifest?
    @State private var kaynak: Manifest.Kaynak = .gomuluAgYok

    var body: some Scene {
        WindowGroup("YapayZekaLab Codex Kurulumu") {
            Group {
                if let m = manifest {
                    ContentView(manifest: m, kaynak: kaynak)
                } else {
                    ProgressView("Ayarlar aliniyor…")
                        .frame(width: 460, height: 470)
                        .task {
                            let (m, k) = await Manifest.yukle()
                            manifest = m; kaynak = k
                        }
                }
            }
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
