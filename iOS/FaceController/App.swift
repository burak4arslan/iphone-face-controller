import SwiftUI

// iPhone Face Controller: drive racing games with your face. The front (Face ID / TrueDepth) camera tracks your face,
// expressions become steering, gas and brake, and the values go over Wi-Fi to a small receiver on your computer
// (windows/face_controller.py → virtual Xbox controller, or mac/ → keyboard).
@main
struct FaceControllerApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { FaceDriveView() }
        }
    }
}

/// Turkish if the phone's first language is Turkish, otherwise English.
func L(_ tr: String, _ en: String) -> String {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("tr") ? tr : en
}
