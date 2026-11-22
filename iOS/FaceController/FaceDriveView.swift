import ARKit
import Network
import SceneKit
import SwiftUI

// The front Face ID (TrueDepth) camera tracks the face; expressions become steering / gas / brake and go to the computer over UDP.
// Head tilt (or turn) = steering, smile (or open mouth) = gas, pucker / cheek puff = brake (reverse when stopped),
// raised brows = nitro, one-eye wink = handbrake. A normal blink (both eyes) does nothing.
// Angles are measured against the calibrated "straight" pose (Center button), so it doesn't matter how the phone stands.
// Face tracking needs some light (a desk lamp is enough; it doesn't work in total darkness).
// (TR) Ön Face ID kamerası yüzü izler: baş eğ = direksiyon, gülümse = gaz, dudak büz / yanak şişir = fren, kaş = nitro, tek göz = el freni.

final class YuzSurusController: NSObject, ObservableObject, ARSCNViewDelegate {
    enum Direksiyon: String, CaseIterable, Identifiable {
        case eg = "Baş eğ", cevir = "Baş çevir"      // raw values are only storage keys
        var id: String { rawValue }
        var ad: String { self == .eg ? L("Baş eğ", "Head tilt") : L("Baş çevir", "Head turn") }
    }

    enum GazKaynagi: String, CaseIterable, Identifiable {
        case gulumse = "Gülümse", agiz = "Ağız", otomatik = "Otomatik"
        var id: String { rawValue }
        var ad: String {
            switch self {
            case .gulumse: return L("Gülümse", "Smile")
            case .agiz: return L("Ağız", "Mouth")
            case .otomatik: return L("Otomatik", "Auto")
            }
        }
    }

    // Ekranda görünenler
    @Published var yuzVar = false
    @Published var direksiyon = 0.0
    @Published var gaz = 0.0
    @Published var fren = 0.0
    @Published var nitro = false
    @Published var elFreni = false
    @Published var macAdi: String?
    @Published var macTuslar = ""
    @Published var macIzin = true
    @Published var macAcik = true
    @Published var durum = L("Hazırlanıyor…", "Starting…")

    // Ayarlar
    // Ayarlar telefonda saklanır: uygulama yeniden yüklenince sıfırlanmasın
    @Published var yontem: Direksiyon = .eg { didSet { kilit.lock(); ayarYontem = yontem; kilit.unlock(); UserDefaults.standard.set(yontem.rawValue, forKey: "yuz.yontem") } }
    @Published var ters = false { didSet { kilit.lock(); ayarTers = ters; kilit.unlock(); UserDefaults.standard.set(ters, forKey: "yuz.ters2") } }
    @Published var gazKaynagi: GazKaynagi = .gulumse { didSet { kilit.lock(); ayarGaz = gazKaynagi; kilit.unlock(); UserDefaults.standard.set(gazKaynagi.rawValue, forKey: "yuz.gaz") } }
    @Published var aci = 20.0 { didSet { kilit.lock(); ayarAci = aci; kilit.unlock(); UserDefaults.standard.set(aci, forKey: "yuz.aci") } }   // tam direksiyon için derece

    let sahneGorunumu = ARSCNView(frame: .zero)
    private var yuzGeometrisi: ARSCNFaceGeometry?
    private let ag = YuzAgi()
    private let kilit = NSLock()
    private var ayarYontem: Direksiyon = .eg
    private var ayarTers = false
    private var ayarAci = 20.0
    private var ayarGaz: GazKaynagi = .gulumse
    private var notr: simd_float3x3?          // kalibrasyondaki baş duruşu
    private var kalibreIste = true
    private var oturum = UInt32.random(in: 1...UInt32.max)
    private var sira: UInt64 = 0
    private var sonEkran: TimeInterval = 0
    private var sonMacCevabi = Date.distantPast
    private var yumusakDireksiyon = 0.0

    override init() {
        super.init()
        let k = UserDefaults.standard
        if let y = k.string(forKey: "yuz.yontem").flatMap(Direksiyon.init(rawValue:)) { yontem = y }
        if let g = k.string(forKey: "yuz.gaz").flatMap(GazKaynagi.init(rawValue:)) { gazKaynagi = g }
        if k.object(forKey: "yuz.aci") != nil { aci = k.double(forKey: "yuz.aci") }
        ters = k.bool(forKey: "yuz.ters2")
        sahneGorunumu.delegate = self
        sahneGorunumu.automaticallyUpdatesLighting = false
        sahneGorunumu.rendersCameraGrain = false
        ag.cevapGeldi = { [weak self] c in
            guard let self else { return }
            self.sonMacCevabi = Date()
            self.macAdi = c.ad
            self.macTuslar = c.tuslar
            self.macIzin = c.izin
            self.macAcik = c.acik
        }
    }

    func baslat() {
        guard ARFaceTrackingConfiguration.isSupported else {
            durum = L("Bu telefonda Face ID kamerası yok", "This iPhone has no Face ID camera")
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        let ayar = ARFaceTrackingConfiguration()
        ayar.maximumNumberOfTrackedFaces = 1
        sahneGorunumu.session.run(ayar, options: [.resetTracking, .removeExistingAnchors])
        kilit.lock(); kalibreIste = true; kilit.unlock()
        ag.baslat()
        durum = L("Yüzünü ön kameraya göster", "Show your face to the front camera")
    }

    func durdur() {
        // Mac tuşları bıraksın diye son paket "yüz yok"
        gonder(takip: false, d: 0, g: 0, f: 0, n: false, e: false)
        UIApplication.shared.isIdleTimerDisabled = false
        sahneGorunumu.session.pause()
        ag.durdur()
    }

    /// Şu anki baş duruşunu "düz" kabul et
    func ortala() {
        kilit.lock(); kalibreIste = true; kilit.unlock()
    }

    var macBagli: Bool { macAdi != nil && Date().timeIntervalSince(sonMacCevabi) < 2 }

    // MARK: ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor, let cihaz = sahneGorunumu.device,
              let geometri = ARSCNFaceGeometry(device: cihaz) else { return nil }
        if let m = geometri.firstMaterial {
            m.fillMode = .lines
            m.lightingModel = .constant
            m.diffuse.contents = UIColor(red: 0.35, green: 1, blue: 0.45, alpha: 0.9)
        }
        yuzGeometrisi = geometri
        return SCNNode(geometry: geometri)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let yuz = anchor as? ARFaceAnchor else { return }
        yuzGeometrisi?.update(from: yuz.geometry)
        guard yuz.isTracked else {
            gonder(takip: false, d: 0, g: 0, f: 0, n: false, e: false)
            ekranaYaz(takip: false, d: 0, g: 0, f: 0, n: false, e: false)
            return
        }

        let t = yuz.transform
        let donus = simd_float3x3(simd_make_float3(t.columns.0), simd_make_float3(t.columns.1), simd_make_float3(t.columns.2))
        kilit.lock()
        if kalibreIste { notr = donus; kalibreIste = false; yumusakDireksiyon = 0 }
        let yontem = ayarYontem, tersMi = ayarTers, tamAci = ayarAci, gazYolu = ayarGaz
        let notr = self.notr ?? donus
        kilit.unlock()

        // Düz bakışa göre dönüş: yüzün kendi eksenlerinde
        let goreli = notr.transpose * donus
        let derece: Double
        switch yontem {
        case .eg: derece = Double(atan2(goreli.columns.0.y, goreli.columns.0.x)) * 180 / .pi      // yüzün ileri ekseni etrafında
        case .cevir: derece = Double(atan2(goreli.columns.2.x, goreli.columns.2.z)) * 180 / .pi   // yüzün dikey ekseni etrafında
        }
        // ARKit'te yüzün x ekseni yüzün kendi soluna bakar: başını sağa eğince açı artı olur → direksiyon sağa.
        // (İlk sürümde işaret tersti; 17 Kasım telefonda "Ters" açılarak doğru çalıştı.)
        // Baş çevirmede tersi: başını sağa çevirince burun yüzün -x yönüne döner, açı eksi çıkar.
        var d = (yontem == .eg ? derece : -derece) / tamAci
        if tersMi { d = -d }
        if abs(d) < 0.08 { d = 0 }                  // ortada küçük titremeler direksiyonu oynatmasın
        d = max(-1, min(1, d))
        yumusakDireksiyon += (d - yumusakDireksiyon) * 0.5
        d = yumusakDireksiyon

        let s = yuz.blendShapes
        func v(_ k: ARFaceAnchor.BlendShapeLocation) -> Double { s[k]?.doubleValue ?? 0 }
        func olcek(_ x: Double, _ alt: Double, _ ust: Double) -> Double { max(0, min(1, (x - alt) / (ust - alt))) }

        let f = olcek(max(v(.mouthPucker), v(.cheekPuff)), 0.35, 0.7)
        let g: Double
        switch gazYolu {
        case .gulumse: g = olcek((v(.mouthSmileLeft) + v(.mouthSmileRight)) / 2, 0.2, 0.65)
        case .agiz: g = olcek(v(.jawOpen), 0.15, 0.55)
        case .otomatik: g = f > 0.1 ? 0 : 1          // fren yaparken gaz bırakılır
        }
        let n = v(.browInnerUp) > 0.55
        let sol = v(.eyeBlinkLeft), sag = v(.eyeBlinkRight)
        let e = (sol > 0.6 && sag < 0.35) || (sag > 0.6 && sol < 0.35)

        gonder(takip: true, d: d, g: g, f: f, n: n, e: e)
        ekranaYaz(takip: true, d: d, g: g, f: f, n: n, e: e)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        gonder(takip: false, d: 0, g: 0, f: 0, n: false, e: false)
        ekranaYaz(takip: false, d: 0, g: 0, f: 0, n: false, e: false)
    }

    private func gonder(takip: Bool, d: Double, g: Double, f: Double, n: Bool, e: Bool) {
        kilit.lock(); sira += 1; let s = sira; kilit.unlock()
        ag.gonder(YuzSurusPaketi(oturum: oturum, sira: s, takip: takip, direksiyon: d, gaz: g, fren: f, nitro: n, elFreni: e))
    }

    private func ekranaYaz(takip: Bool, d: Double, g: Double, f: Double, n: Bool, e: Bool) {
        let simdi = CACurrentMediaTime()
        guard simdi - sonEkran > 1.0 / 30 || !takip else { return }
        sonEkran = simdi
        DispatchQueue.main.async {
            self.yuzVar = takip
            self.direksiyon = d; self.gaz = g; self.fren = f; self.nitro = n; self.elFreni = e
            self.durum = takip ? L("Sürüyorsun", "Driving") : L("Yüz görünmüyor (ışık az olabilir)", "No face (maybe too dark)")
        }
    }
}

// Finds the receiver (Windows or Mac) via Bonjour on the same Wi-Fi, sends packets and listens for its replies.
final class YuzAgi: @unchecked Sendable {
    var cevapGeldi: ((YuzSurusCevabi) -> Void)?

    private let kuyruk = DispatchQueue(label: "yuz.ag")
    private var tarayici: NWBrowser?
    private var baglanti: NWConnection?
    private var hedef: NWEndpoint?
    private let kodlayici = JSONEncoder()

    func baslat() {
        kuyruk.async {
            guard self.tarayici == nil else { return }
            let tarayici = NWBrowser(for: .bonjour(type: YuzAg.servis, domain: nil), using: .udp)
            tarayici.browseResultsChangedHandler = { sonuclar, _ in
                let yeni = sonuclar.first?.endpoint
                if yeni != self.hedef {
                    self.hedef = yeni
                    self.baglan()
                }
            }
            tarayici.start(queue: self.kuyruk)
            self.tarayici = tarayici
        }
    }

    func durdur() {
        kuyruk.async {
            self.tarayici?.cancel(); self.tarayici = nil
            self.baglanti?.cancel(); self.baglanti = nil
            self.hedef = nil
        }
    }

    func gonder(_ paket: YuzSurusPaketi) {
        kuyruk.async {
            guard let baglanti = self.baglanti, let veri = try? self.kodlayici.encode(paket) else { return }
            baglanti.send(content: veri, completion: .idempotent)
        }
    }

    private func baglan() {
        baglanti?.cancel()
        baglanti = nil
        guard let hedef else { return }
        let yeni = NWConnection(to: hedef, using: .udp)
        yeni.start(queue: kuyruk)
        baglanti = yeni
        dinle(yeni)
    }

    private func dinle(_ c: NWConnection) {
        c.receiveMessage { [weak self] veri, _, _, hata in
            guard let self, c === self.baglanti else { return }
            if let veri, let cevap = try? JSONDecoder().decode(YuzSurusCevabi.self, from: veri) {
                let geri = self.cevapGeldi
                DispatchQueue.main.async { geri?(cevap) }
            }
            if hata == nil { self.dinle(c) }
        }
    }
}

private struct YuzSahnesi: UIViewRepresentable {
    let gorunum: ARSCNView
    func makeUIView(context: Context) -> ARSCNView { gorunum }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct FaceDriveView: View {
    @StateObject private var c = YuzSurusController()
    @State private var temiz = false

    var body: some View {
        ZStack(alignment: .bottom) {
            YuzSahnesi(gorunum: c.sahneGorunumu)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { temiz.toggle() } }
            VStack(spacing: 0) {
                ustBilgi
                Spacer()
                if !temiz { panel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(L("Yüzle sür", "Face Controller"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(temiz ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(temiz)
        .onAppear { c.baslat() }
        .onDisappear { c.durdur() }
    }

    private var ustBilgi: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 8) {
                Circle().fill(c.macBagli ? (c.macIzin && c.macAcik ? .green : .orange) : .red).frame(width: 10, height: 10)
                Text(macYazisi).font(.footnote.bold())
                Spacer()
                if c.macBagli, !c.macTuslar.isEmpty {
                    Text(c.macTuslar).font(.system(.footnote, design: .monospaced).bold())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.horizontal, 12).padding(.top, 8)
        }
    }

    private var macYazisi: String {
        guard c.macBagli, let ad = c.macAdi else { return L("Bilgisayar aranıyor… (alıcı açık mı, aynı Wi-Fi mı?)", "Looking for the computer… (receiver running, same Wi-Fi?)") }
        if !c.macIzin { return L("\(ad): Erişilebilirlik izni yok", "\(ad): no Accessibility permission") }
        if !c.macAcik { return L("\(ad): kapalı", "\(ad): paused") }
        return L("Bağlı: \(ad)", "Connected: \(ad)")
    }

    private var panel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "steeringwheel")
                    .font(.system(size: 54, weight: .semibold))
                    .rotationEffect(.degrees(c.direksiyon * 90))
                    .foregroundStyle(c.yuzVar ? .white : .gray)
                    .frame(width: 70)
                VStack(spacing: 8) {
                    cubuk(L("Gaz", "Gas"), c.gaz, .green)
                    cubuk(L("Fren", "Brake"), c.fren, .red)
                    HStack(spacing: 8) {
                        isaret("Nitro", "flame.fill", c.nitro, .orange)
                        isaret(L("El freni", "Handbrake"), "exclamationmark.octagon.fill", c.elFreni, .yellow)
                    }
                }
            }
            Text(c.durum).font(.caption).foregroundStyle(.secondary)
            Picker(L("Gaz", "Gas"), selection: $c.gazKaynagi) {
                ForEach(YuzSurusController.GazKaynagi.allCases) { Text(L("Gaz: ", "Gas: ") + $0.ad).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker(L("Direksiyon", "Steering"), selection: $c.yontem) {
                ForEach(YuzSurusController.Direksiyon.allCases) { Text($0.ad).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(L("Hassasiyet", "Sensitivity")).font(.subheadline)
                Slider(value: $c.aci, in: 8...35, step: 1)
                Text("\(Int(c.aci))°").font(.subheadline.monospacedDigit()).frame(width: 36)
            }
            HStack {
                Toggle(isOn: $c.ters) { Text(L("Ters", "Reverse")).lineLimit(1).fixedSize() }.fixedSize()
                Spacer()
                Button { c.ortala() } label: { Label(L("Ortala", "Center"), systemImage: "scope") }
                    .buttonStyle(.borderedProminent)
            }
            Text(L("Gülümse / ağız = gaz · Dudak büz / yanak şişir = fren · Kaş = nitro · Tek göz kırp = el freni · Ekrana dokun: gizle",
                    "Smile / mouth = gas · Pucker / puff cheeks = brake · Brows = nitro · One-eye wink = handbrake · Tap screen: hide"))
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    private func cubuk(_ ad: String, _ deger: Double, _ renk: Color) -> some View {
        HStack(spacing: 8) {
            Text(ad).font(.subheadline).frame(width: 48, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(renk).frame(width: g.size.width * deger)
                }
            }
            .frame(height: 10)
        }
    }

    private func isaret(_ ad: String, _ simge: String, _ acik: Bool, _ renk: Color) -> some View {
        Label(ad, systemImage: simge)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(acik ? renk : .white.opacity(0.12), in: Capsule())
            .foregroundStyle(acik ? .black : .white.opacity(0.6))
    }
}
