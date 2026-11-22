import Foundation

// Wire format between the iPhone app and the receivers (windows/face_controller.py, mac/main.swift). JSON over UDP,
// the receiver advertises itself on Bonjour as _denemeyuz._udp (name kept for compatibility with the first version).
// (TR) Telefon ile alıcılar arasındaki JSON paketleri. Mac alıcısı bu dosyayı da derler (mac/build.sh).
enum YuzAg {
    static let servis = "_denemeyuz._udp"
}

// Phone → computer, on every ARKit frame. Each packet is the current state, so a lost packet is fixed by the next one.
struct YuzSurusPaketi: Codable {
    var oturum: UInt32
    var sira: UInt64
    var takip: Bool         // face tracked? false → the receiver releases everything
    var direksiyon: Double  // steering -1 (left) … +1 (right)
    var gaz: Double         // 0 … 1 gas (smile, or mouth open)
    var fren: Double        // 0 … 1 brake (pucker / cheek puff)
    var nitro: Bool         // raised brows
    var elFreni: Bool       // one-eye wink (handbrake)
}

// Computer → phone: name, state and what is pressed right now (shown at the top of the phone screen).
struct YuzSurusCevabi: Codable {
    var ad: String
    var acik: Bool
    var izin: Bool          // Mac only: without Accessibility permission keys don't reach the game
    var tuslar: String      // e.g. "Left Gas"
}
