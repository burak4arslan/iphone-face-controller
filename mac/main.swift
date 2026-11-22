import AppKit
import ApplicationServices
import Network
import SwiftUI

// Face Controller, Mac receiver: presses keyboard keys from the iPhone app's face values; the game thinks it is a real keyboard.
// (TR) Telefondaki uygulamadan gelen değerlerle klavye tuşlarına basar. Arayüz Türkçedir.
// Direksiyon ve gaz kademeli: tuş saniyede 10 kez, değer kadar süre basılı tutulur (yarım direksiyon = sürenin yarısı).
// Güvenlik: 0,3 sn paket gelmezse, yüz kaybolursa, "Açık" kapanınca ya da uygulama kapanınca bütün tuşlar bırakılır.
// Tuşların oyuna gitmesi için Erişilebilirlik izni gerekir. Derleme: ./build.sh. YUZ_KURU=1: tuşa basmaz, yazar.
@main
struct YuzDireksiyonApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var alici = YuzAlici.ortak

    var body: some Scene {
        WindowGroup("Yüz Direksiyon") {
            AnaGorunum(alici: alici).frame(width: 420)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { YuzAlici.ortak.hepsiniBirak() }
    }
}

enum Tus: String, CaseIterable, Hashable {
    case gaz, fren, sol, sag, nitro, elFreni
}

enum TusTakimi: String, CaseIterable, Identifiable {
    case oklar = "Ok tuşları", wasd = "WASD"
    var id: String { rawValue }
    // macOS sanal tuş kodları
    func kod(_ t: Tus) -> CGKeyCode {
        switch (self, t) {
        case (.oklar, .gaz): return 126   // ↑
        case (.oklar, .fren): return 125  // ↓
        case (.oklar, .sol): return 123   // ←
        case (.oklar, .sag): return 124   // →
        case (.wasd, .gaz): return 13     // W
        case (.wasd, .fren): return 1     // S
        case (.wasd, .sol): return 0      // A
        case (.wasd, .sag): return 2      // D
        case (_, .nitro): return 56       // sol Shift
        case (_, .elFreni): return 49     // boşluk
        }
    }
    func ad(_ t: Tus) -> String {
        switch (self, t) {
        case (.oklar, .gaz): return "↑"
        case (.oklar, .fren): return "↓"
        case (.oklar, .sol): return "←"
        case (.oklar, .sag): return "→"
        case (.wasd, .gaz): return "W"
        case (.wasd, .fren): return "S"
        case (.wasd, .sol): return "A"
        case (.wasd, .sag): return "D"
        case (_, .nitro): return "Shift"
        case (_, .elFreni): return "Boşluk"
        }
    }
}

@MainActor
final class YuzAlici: ObservableObject {
    static let ortak = YuzAlici()

    @Published var acik: Bool = UserDefaults.standard.object(forKey: "acik") as? Bool ?? true {
        didSet { UserDefaults.standard.set(acik, forKey: "acik"); if !acik { hepsiniBirak() } }
    }
    @Published var takim: TusTakimi = TusTakimi(rawValue: UserDefaults.standard.string(forKey: "takim") ?? "") ?? .oklar {
        didSet { UserDefaults.standard.set(takim.rawValue, forKey: "takim"); hepsiniBirak() }
    }
    @Published var kademeli: Bool = UserDefaults.standard.object(forKey: "kademeli") as? Bool ?? true {
        didSet { UserDefaults.standard.set(kademeli, forKey: "kademeli") }
    }

    @Published private(set) var bagli = false
    @Published private(set) var takip = false
    @Published private(set) var direksiyon = 0.0
    @Published private(set) var gaz = 0.0
    @Published private(set) var fren = 0.0
    @Published private(set) var basili: Set<Tus> = []
    @Published private(set) var izin = AXIsProcessTrusted()
    @Published private(set) var dinleyiciDurumu = "başlıyor"

    let ad = Host.current().localizedName ?? "Mac"
    private let kuru = ProcessInfo.processInfo.environment["YUZ_KURU"] == "1"
    private var dinleyici: NWListener?
    private var baglantilar: [NWConnection] = []
    private let kaynak = CGEventSource(stateID: .hidSystemState)
    private var son: YuzSurusPaketi?
    private var sonPaketZamani = Date.distantPast
    private var sonCevap = Date.distantPast
    private var sonOturum: UInt32 = 0
    private var sonSira: UInt64 = 0
    private var dongu = 0          // 0…9: saniyede 10 kez dönen kademe sayacı
    private var zamanlayici: Timer?
    @Published private(set) var oyunBagli = false
    private var sonOyunIstegi = Date.distantPast
    private var oyunSunucusu: NWListener?
    static let oyunPortu: UInt16 = 8765

    // MARK: Oyun sunucusu: http://127.0.0.1:8765/ oyunu verir, /durum yüz verisini JSON olarak verir.
    // Oyun saniyede ~60 kez /durum'u okur; tuş basmaya gerek kalmaz, direksiyon ve gaz tam kademeli olur.
    private func oyunSunucusunuBaslat() {
        let ayar = NWParameters.tcp
        ayar.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.oyunPortu)!)
        ayar.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: ayar) else { return }
        l.newConnectionHandler = { [weak self] c in
            c.start(queue: .main)
            c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { veri, _, _, _ in
                MainActor.assumeIsolated { self?.oyunIstegi(c, veri ?? Data()) }
            }
        }
        l.start(queue: .main)
        oyunSunucusu = l
    }

    private func oyunIstegi(_ c: NWConnection, _ veri: Data) {
        let satir = String(decoding: veri.prefix(200), as: UTF8.self).split(separator: "\r\n").first ?? ""
        let yol = satir.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        var govde = Data(), tur = "text/plain", kod = "200 OK"
        if yol.hasPrefix("/durum") {
            sonOyunIstegi = Date()
            let canli = Date().timeIntervalSince(sonPaketZamani) < 0.3
            let p = son
            let takipVar = acik && canli && (p?.takip ?? false)
            let d: [String: Any] = [
                "bagli": acik && Date().timeIntervalSince(sonPaketZamani) < 1.5, "takip": takipVar,
                "direksiyon": takipVar ? p!.direksiyon : 0, "gaz": takipVar ? p!.gaz : 0, "fren": takipVar ? p!.fren : 0,
                "nitro": takipVar && p!.nitro, "elFreni": takipVar && p!.elFreni,
            ]
            govde = (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
            tur = "application/json"
        } else if yol == "/" || yol.hasPrefix("/yaris") || yol.hasPrefix("/?") || yol.hasPrefix("/#"),
                  let url = Bundle.main.url(forResource: "yaris", withExtension: "html"), let html = try? Data(contentsOf: url) {
            govde = html; tur = "text/html; charset=utf-8"
        } else {
            kod = "404 Not Found"
        }
        let baslik = "HTTP/1.1 \(kod)\r\nContent-Type: \(tur)\r\nContent-Length: \(govde.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        c.send(content: Data(baslik.utf8) + govde, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: Kayıt: mac-yuz/kayit/<gün>.csv, saniyede 10 satır (sorun olunca okumak için)
    private var kayitDosyasi: FileHandle?
    private func kayitYaz(_ p: YuzSurusPaketi) {
        if kayitDosyasi == nil {
            let klasor = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("IdeaProjects/CarPlayDeneme/mac-yuz/kayit")
            try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let url = klasor.appendingPathComponent(f.string(from: Date()) + ".csv")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data("saat,takip,direksiyon,gaz,fren,nitro,elFreni,oyun,tuslar\n".utf8))
            }
            kayitDosyasi = try? FileHandle(forWritingTo: url)
            kayitDosyasi?.seekToEndOfFile()
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.S"
        let tuslar = Tus.allCases.filter { basili.contains($0) }.map { takim.ad($0) }.joined(separator: " ")
        let satir = String(format: "%@,%d,%.2f,%.2f,%.2f,%d,%d,%d,%@\n", f.string(from: Date()), p.takip ? 1 : 0,
                           p.direksiyon, p.gaz, p.fren, p.nitro ? 1 : 0, p.elFreni ? 1 : 0, oyunBagli ? 1 : 0, tuslar)
        kayitDosyasi?.write(Data(satir.utf8))
    }

    init() {
        baslat()
        oyunSunucusunuBaslat()
    }

    func izinIste() {
        let secenek = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        izin = AXIsProcessTrustedWithOptions(secenek)
        if !izin, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Ağ

    private func baslat() {
        do {
            let yeni = try NWListener(using: .udp)
            yeni.service = NWListener.Service(name: ad, type: YuzAg.servis)
            yeni.stateUpdateHandler = { [weak self] durum in
                let metin: String
                switch durum {
                case .ready: metin = "hazır"
                case .failed(let hata): metin = "hata: \(hata)"
                case .waiting(let hata): metin = "bekliyor: \(hata)"
                default: metin = "başlıyor"
                }
                DispatchQueue.main.async { self?.dinleyiciDurumu = metin }
            }
            yeni.newConnectionHandler = { [weak self] b in
                DispatchQueue.main.async { self?.yeniBaglanti(b) }
            }
            yeni.start(queue: .main)
            dinleyici = yeni
        } catch {
            dinleyiciDurumu = "hata: \(error)"
        }
        // Saniyede 100 adım: tuşların kademeli basılması ve güvenlik kontrolü
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.adim() }
        }
        RunLoop.main.add(zamanlayici!, forMode: .common)
    }

    private func yeniBaglanti(_ b: NWConnection) {
        baglantilar.append(b)
        while baglantilar.count > 4 { baglantilar.removeFirst().cancel() }
        b.start(queue: .main)
        dinle(b)
    }

    private func dinle(_ b: NWConnection) {
        b.receiveMessage { [weak self] veri, _, _, hata in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let veri, let p = try? JSONDecoder().decode(YuzSurusPaketi.self, from: veri) {
                    self.isle(p, b)
                }
                if hata == nil { self.dinle(b) }
            }
        }
    }

    private func isle(_ p: YuzSurusPaketi, _ b: NWConnection) {
        if p.oturum != sonOturum { sonOturum = p.oturum; sonSira = 0 }
        guard p.sira > sonSira else { return }    // geç gelen eski paket
        sonSira = p.sira
        son = p
        sonPaketZamani = Date()
        if Date().timeIntervalSince(sonCevap) > 0.2 {
            sonCevap = Date()
            let tuslar = Tus.allCases.filter { basili.contains($0) }.map { takim.ad($0) }.joined(separator: " ")
            if let veri = try? JSONEncoder().encode(YuzSurusCevabi(ad: ad, acik: acik, izin: izin, tuslar: tuslar)) {
                b.send(content: veri, completion: .idempotent)
            }
        }
    }

    // MARK: Tuşlar

    private func adim() {
        let canli = Date().timeIntervalSince(sonPaketZamani) < 0.3
        bagli = Date().timeIntervalSince(sonPaketZamani) < 1.5
        guard acik, canli, let p = son, p.takip else {
            takip = false
            if !basili.isEmpty { hepsiniBirak() }
            return
        }
        takip = true
        direksiyon = p.direksiyon; gaz = p.gaz; fren = p.fren
        if dongu % 50 == 0 { izin = AXIsProcessTrusted() }
        dongu = (dongu + 1) % 100
        if dongu % 10 == 0 { kayitYaz(p) }
        oyunBagli = Date().timeIntervalSince(sonOyunIstegi) < 0.5
        // Kendi oyunumuz değerleri doğrudan okuyorsa tuşa basma (iki kez sürmesin)
        if oyunBagli {
            if !basili.isEmpty { hepsiniBirak() }
            return
        }

        let kademe = Double(dongu % 10) / 10    // 0.0 … 0.9
        func kademeliBas(_ deger: Double) -> Bool {
            guard deger > 0.05 else { return false }
            if !kademeli || deger >= 0.9 { return true }
            return kademe < deger
        }

        var istenen: Set<Tus> = []
        let frenVar = p.fren > 0.4
        if frenVar { istenen.insert(.fren) } else if kademeliBas(p.gaz) { istenen.insert(.gaz) }
        if p.direksiyon < 0, kademeliBas(-p.direksiyon) { istenen.insert(.sol) }
        if p.direksiyon > 0, kademeliBas(p.direksiyon) { istenen.insert(.sag) }
        if p.nitro { istenen.insert(.nitro) }
        if p.elFreni { istenen.insert(.elFreni) }

        for t in basili.subtracting(istenen) { gonder(t, asagi: false) }
        for t in istenen.subtracting(basili) { gonder(t, asagi: true) }
        basili = istenen
    }

    func hepsiniBirak() {
        for t in basili { gonder(t, asagi: false) }
        basili = []
    }

    private func gonder(_ t: Tus, asagi: Bool) {
        if kuru { FileHandle.standardError.write("\(asagi ? "bas" : "bırak") \(takim.ad(t))\n".data(using: .utf8)!); return }
        let kod = takim.kod(t)
        guard let olay = CGEvent(keyboardEventSource: kaynak, virtualKey: kod, keyDown: asagi) else { return }
        if t == .nitro {
            // Shift bir değiştirici tuş: oyunlar onu "flagsChanged" olarak görür
            olay.type = .flagsChanged
            olay.flags = asagi ? .maskShift : []
        }
        olay.post(tap: .cghidEventTap)
    }
}

struct AnaGorunum: View {
    @ObservedObject var alici: YuzAlici

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(alici.bagli ? (alici.takip ? .green : .orange) : .red).frame(width: 12, height: 12)
                Text(alici.bagli ? (alici.takip ? "Telefon bağlı, yüz görülüyor" : "Telefon bağlı, yüz yok") : "Telefon bekleniyor (iPhone: Face Controller)")
                    .font(.headline)
            }
            Button {
                if let url = URL(string: "http://127.0.0.1:\(YuzAlici.oyunPortu)/") {
                    let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
                    NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
                }
            } label: { Label("Oyunu aç (Yüzle Yarış)", systemImage: "flag.checkered") }
            .controlSize(.large)
            Toggle("Açık (kapatınca bütün tuşlar bırakılır)", isOn: $alici.acik)
            Picker("Tuşlar", selection: $alici.takim) {
                ForEach(TusTakimi.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if alici.oyunBagli {
                Label("Yüzle Yarış doğrudan bağlı: tuş basılmıyor, değerler oyuna kademeli gidiyor", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Toggle("Kademeli direksiyon ve gaz (kapalıysa yarısını geçince tam basar)", isOn: $alici.kademeli)

            HStack(spacing: 8) {
                ForEach([Tus.sol, .gaz, .fren, .sag, .nitro, .elFreni], id: \.self) { t in
                    Text(alici.takim.ad(t))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(minWidth: 44, minHeight: 40)
                        .padding(.horizontal, 4)
                        .background(alici.basili.contains(t) ? Color.green : Color.gray.opacity(0.2),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(alici.basili.contains(t) ? .black : .primary)
                }
            }
            Text(String(format: "Direksiyon %+.2f   Gaz %.2f   Fren %.2f", alici.direksiyon, alici.gaz, alici.fren))
                .font(.system(.body, design: .monospaced))

            if !alici.izin {
                HStack {
                    Text("Erişilebilirlik izni yok: tuşlar oyuna gitmez.").foregroundStyle(.orange)
                    Button("İzin ver") { alici.izinIste() }
                }
            }
            Text("Ağ: \(alici.dinleyiciDurumu) · \(alici.ad)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
