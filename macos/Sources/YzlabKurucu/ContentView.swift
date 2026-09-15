import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var kurucu: Kurucu
    private let kaynak: Manifest.Kaynak

    @State private var anahtar = ""
    @State private var model: Manifest.Model
    @State private var anahtarGiris = false
    @State private var claude = false
    @State private var durum: Durum = .bos
    @State private var dogrulamaGorevi: Task<Void, Never>?
    @State private var kurulu = false

    enum Durum: Equatable {
        case bos, dogrulaniyor, gecerli(String), kuruluyor(String), bitti, hata(String)
    }

    init(manifest: Manifest, kaynak: Manifest.Kaynak) {
        _kurucu = StateObject(wrappedValue: Kurucu(manifest: manifest))
        self.kaynak = kaynak
        let v = manifest.codex.models.first { $0.id == manifest.codex.defaultModel }
            ?? manifest.codex.models[0]
        _model = State(initialValue: v)
    }

    private var anahtarGecerli: Bool { if case .gecerli = durum { return true }; return false }
    private var mesgul: Bool {
        if case .kuruluyor = durum { return true }
        if case .dogrulaniyor = durum { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            baslik
            anahtarAlani
            modelAlani
            secenekler
            Divider()
            guvence
            Spacer(minLength: 0)
            altBar
        }
        .padding(26)
        .frame(width: 480, height: 580)
        .onAppear {
            kurulu = kurucu.kuruluMu || kurucu.claudeKuruluMu
            panodanAnahtar()
        }
    }

    /// TEK TIK: panoda `yzk_live_…` varsa alana kendiliginden girer.
    private func panodanAnahtar() {
        guard anahtar.isEmpty,
              let s = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              s.hasPrefix(kurucu.manifest.api.keyPrefix), s.count >= 20, s.count <= 200,
              !s.contains(" "), !s.contains("\n") else { return }
        anahtar = s
    }

    private var baslik: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("YapayZekaLab").font(.system(size: 21, weight: .semibold))
            Text("Codex masaustu kurulumu").font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private var anahtarAlani: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API anahtarin").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            SecureField(kurucu.manifest.api.keyPrefix + "…", text: $anahtar)
                .textFieldStyle(.roundedBorder)
                .disabled(mesgul)
                .onChange(of: anahtar) { yeni in anahtarDegisti(yeni) }
            durumSatiri
        }
    }

    @ViewBuilder private var durumSatiri: some View {
        switch durum {
        case .bos:
            Text("Panelinden kopyalayip yapistir.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .dogrulaniyor:
            Label("Kontrol ediliyor…", systemImage: "ellipsis.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .gecerli(let bakiye):
            Label("Anahtar gecerli · bakiye \u{20BA}\(bakiye)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.green)
        case .kuruluyor(let a):
            Label(a, systemImage: "gearshape").font(.system(size: 11)).foregroundStyle(.secondary)
        case .bitti:
            Label(claude
                  ? "Kuruldu. Codex'i ac ve yaz. Claude Code: yeni terminalde `claude`."
                  : "Kuruldu. Codex'i ac ve yaz — istekler YapayZekaLab'dan gecer.",
                  systemImage: "checkmark.seal.fill")
                .font(.system(size: 11)).foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
        case .hata(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelAlani: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Picker("", selection: $model) {
                ForEach(kurucu.manifest.codex.models) { m in
                    Text(m.label).tag(m)
                }
            }
            .labelsHidden()
            .disabled(mesgul)
        }
    }

    private var secenekler: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("ChatGPT hesabim yerine yalniz anahtarla gir", isOn: $anahtarGiris)
                    .disabled(mesgul)
                Text("Codex'te hala \"hakkiniz yok / usage limit\" cikiyorsa isaretle. Geri Al hesabini geri getirir.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Claude Code'u da bagla (terminal + Claude masaustu)", isOn: $claude)
                .disabled(mesgul)
        }
    }

    private var guvence: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Mevcut ayarlarin korunur", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
            Text("Codex'in config.toml dosyasina isaretli bir blok eklenir, onceki hali saklanir. ChatGPT girisin durur. Codex aciksa kapatilip kurulumdan sonra yeniden acilir. Geri Al her seyi birebir geri koyar.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch kaynak {
            case .canli: EmptyView()
            case .gomuluAgYok:
                Text("Sunucuya ulasilamadi — gomulu ayarlar kullaniliyor.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            case .gomuluEskiSema:
                Text("Sunucudaki ayar dosyasi eski surum — bu kurucunun gomulu ayarlari kullaniliyor.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var altBar: some View {
        HStack {
            if kurulu {
                Button("Geri Al") {
                    kurucu.geriAl()
                    kurulu = kurucu.kuruluMu || kurucu.claudeKuruluMu
                    durum = .hata(kurucu.adim)
                }
                .disabled(mesgul)
            }
            Spacer()
            if mesgul { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button(kurulu ? "Yeniden Kur" : "Kur") { kurulumuBaslat() }
                .keyboardShortcut(.defaultAction)
                .disabled(!anahtarGecerli || mesgul)
        }
    }

    // MARK: - Eylemler

    private func anahtarDegisti(_ yeni: String) {
        dogrulamaGorevi?.cancel()
        let temiz = yeni.trimmingCharacters(in: .whitespacesAndNewlines)
        guard temiz.count >= 20 else { durum = .bos; return }
        durum = .dogrulaniyor
        dogrulamaGorevi = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            do {
                let b = try await kurucu.anahtariDogrula(temiz)
                if !Task.isCancelled { durum = .gecerli(b.tl) }
            } catch {
                if !Task.isCancelled { durum = .hata(error.localizedDescription) }
            }
        }
    }

    private func kurulumuBaslat() {
        let temiz = anahtar.trimmingCharacters(in: .whitespacesAndNewlines)
        var kapatIzni = false
        if !Kurucu.acikCodexUygulamalari().isEmpty {
            let a = NSAlert()
            a.messageText = "Codex acik"
            a.informativeText = "Ayarin gecmesi icin Codex kapatilacak ve kurulum bitince yeniden acilacak."
            a.addButton(withTitle: "Kapat ve kur")
            a.addButton(withTitle: "Vazgec")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            kapatIzni = true
        }
        Task {
            do {
                durum = .kuruluyor("Basliyor…")
                let izle = Task { @MainActor in
                    while kurucu.calisiyor || durum == .kuruluyor("Basliyor…") {
                        if kurucu.calisiyor { durum = .kuruluyor(kurucu.adim) }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                try await kurucu.kur(anahtar: temiz, model: model, claude: claude,
                                     anahtarGiris: anahtarGiris, codexKapatIzni: kapatIzni)
                izle.cancel()
                kurulu = true
                durum = .bitti
            } catch {
                kurulu = kurucu.kuruluMu || kurucu.claudeKuruluMu
                durum = .hata(error.localizedDescription)
            }
        }
    }
}
