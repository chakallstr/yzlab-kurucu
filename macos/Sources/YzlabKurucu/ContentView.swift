import SwiftUI

struct ContentView: View {
    @StateObject private var kurucu: Kurucu
    private let manifestCanli: Bool

    @State private var anahtar = ""
    @State private var model: Manifest.Model
    @State private var kisayol = true
    @State private var durum: Durum = .bos
    @State private var dogrulamaGorevi: Task<Void, Never>?

    enum Durum: Equatable {
        case bos, dogrulaniyor, gecerli(String), kuruluyor(String), bitti, hata(String)
    }

    init(manifest: Manifest, canli: Bool) {
        _kurucu = StateObject(wrappedValue: Kurucu(manifest: manifest))
        manifestCanli = canli
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
        VStack(alignment: .leading, spacing: 18) {
            baslik
            anahtarAlani
            modelAlani
            Toggle("Terminal kisayolu ekle (yzlab-codex)", isOn: $kisayol)
                .disabled(mesgul)
            Divider()
            guvence
            Spacer(minLength: 0)
            altBar
        }
        .padding(26)
        .frame(width: 460, height: 470)
    }

    private var baslik: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("YapayZekaLab").font(.system(size: 21, weight: .semibold))
            Text("Codex Kurulumu").font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private var anahtarAlani: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API anahtarin").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            SecureField(kurucu.manifest.api.keyPrefix + "…", text: $anahtar)
                .textFieldStyle(.roundedBorder)
                .disabled(mesgul)
                // macOS 13 (Ventura) destegi: yeni iki-parametreli onChange 14+ ister.
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
            Label("Kuruldu. Yeni bir terminal ac ve `codex -p yzlab` yaz.",
                  systemImage: "checkmark.seal.fill")
                .font(.system(size: 11)).foregroundStyle(.green)
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
            Text("Sonradan degistirebilirsin: \(kurucu.manifest.codex.profileFile) icindeki `model` satiri.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var guvence: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("ChatGPT Plus ayarlarina dokunulmaz", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
            Text("Kurulum ayri bir profil dosyasi olusturur. Mevcut config.toml ve auth.json aynen kalir; `codex` eskisi gibi, `codex -p yzlab` bizim uzerimizden calisir.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !manifestCanli {
                Text("Sunucuya ulasilamadi — gomulu ayarlar kullaniliyor.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
    }

    private var altBar: some View {
        HStack {
            if kurucu.kuruluMu {
                Button("Geri Al") { kurucu.geriAl(); durum = .hata(kurucu.adim) }
                    .disabled(mesgul)
            }
            Spacer()
            if mesgul { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button(kurucu.kuruluMu ? "Yeniden Kur" : "Kur") { kurulumuBaslat() }
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
            // Yapistirma sirasinda her karakterde istek atmamak icin kisa bekleme.
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
        Task {
            do {
                durum = .kuruluyor("Basliyor…")
                let izle = Task { @MainActor in
                    while kurucu.calisiyor {
                        durum = .kuruluyor(kurucu.adim)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                try await kurucu.kur(anahtar: temiz, model: model, kisayol: kisayol)
                izle.cancel()
                durum = .bitti
            } catch {
                durum = .hata(error.localizedDescription)
            }
        }
    }
}
