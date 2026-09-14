import Foundation
import SwiftUI

// Giris noktasi. Ayni ikili uc modda calisir:
//   (pencere)              → SwiftUI kurulum ekrani
//   --selftest             → CI/yerel: kurulum mantiginin invaryantlari (Windows ile birebir)
//   --kur / --geri-al      → basssiz (headless) kurulum: e2e testi ve otomasyon icin
let argv = CommandLine.arguments
if argv.contains("--selftest") {
    setbuf(stdout, nil)
    Task { @MainActor in exit(await SelfTest.calistir()) }
    dispatchMain()
} else if argv.contains("--kur") || argv.contains("--geri-al") {
    setbuf(stdout, nil)
    KomutSatiri.calistir(argv)   // exit() kendi icinde
} else {
    YzlabKurucuApp.main()
}
