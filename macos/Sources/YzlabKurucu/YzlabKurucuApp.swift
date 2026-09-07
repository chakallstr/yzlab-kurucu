import SwiftUI

@main
struct YzlabKurucuApp: App {
    @State private var manifest: Manifest?
    @State private var canli = false

    var body: some Scene {
        WindowGroup("YapayZekaLab Codex Kurulumu") {
            Group {
                if let m = manifest {
                    ContentView(manifest: m, canli: canli)
                } else {
                    ProgressView("Ayarlar aliniyor…")
                        .frame(width: 460, height: 470)
                        .task {
                            let (m, c) = await Manifest.load()
                            manifest = m; canli = c
                        }
                }
            }
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
