# iPhone Face Controller

**Drive racing games with your face.** The iPhone's Face ID camera turns a smile into gas, puffed cheeks into brake and a head tilt into steering, and your PC sees a real Xbox controller.

▶️ Video (Turkish, English audio track available): [I played NFS Underground 2 with only my face](https://youtu.be/7qP2qAYkGS0)

[Türkçe açıklama aşağıda ↓](#türkçe)

## Contents
- [Controls](#controls)
- [How it works](#how-it-works)
- [Quick start (Windows + iPhone)](#quick-start-windows--iphone)
- [Game setup](#game-setup)
- [Mac receiver (optional)](#mac-receiver-optional)
- [App settings](#app-settings)
- [Privacy and safety](#privacy-and-safety)
- [Türkçe](#türkçe)

## Controls

| Your face | Car | Xbox controller |
|---|---|---|
| 😁 Smile | Gas (analog: bigger smile, more gas) | Right trigger |
| 😤 Pucker lips or puff cheeks | Brake, reverse when stopped | Left trigger |
| ↔️ Tilt your head left / right | Steering (analog) | Left stick X |
| 🤨 Raise your eyebrows | Nitro | A |
| 😉 Wink one eye | Handbrake | B |

A normal blink (both eyes) does nothing, so blinking never stops the car.

## How it works

```
iPhone (Face ID camera, ARKit)  ──Wi-Fi, UDP──▶  PC receiver  ──▶  virtual Xbox controller  ──▶  game
   face → steering / gas / brake                windows/face_controller.py    (ViGEmBus)
```

- The iPhone app tracks 52 face shapes with ARKit and sends only a few numbers (steering, gas, brake, nitro, handbrake) to your computer on every frame.
- The receiver finds the phone by itself (Bonjour on the same Wi-Fi) and turns the values into a virtual Xbox 360 controller, so any game with controller support works, including browser games (Gamepad API).

## Quick start (Windows + iPhone)

**You need:** an iPhone with Face ID (iOS 17+), a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to install the app, a Windows PC with Python 3, all on the same Wi-Fi.

1. **Windows receiver**
   ```
   cd windows
   pip install -r requirements.txt     # vgamepad also installs the ViGEmBus driver, accept its setup window
   python face_controller.py
   ```
   If the firewall asks, allow **Private networks** (otherwise the phone can't find the PC).
2. **iPhone app**
   ```
   cp Config/local.env.example Config/local.env   # optional: your Team ID and bundle ID
   ./generate.sh                                   # brew install xcodegen first
   open FaceController.xcodeproj                   # pick your team, run on your iPhone
   ```
   A free Apple ID works for installing on your own phone.
3. Open the app, look straight at the phone and tap **Center**. The top bar should say **Connected: <your PC name>** and show what is pressed (e.g. `Left Gas`).
4. Map the controls in your game (below) and drive.

## Game setup

- Most games pick up the Xbox controller by themselves. In the game's control settings check: steering = left stick, gas = right trigger, brake = left trigger, nitro = A, handbrake = B.
- Tested with **Need for Speed Underground 2** on Windows: free roam up to 140 mph and races, only with the face. If nitro or handbrake don't react, map them to A / B in the game's controls.
- **Old (DirectInput) games** see the two triggers as one combined axis, so gas and brake can't be mapped separately: run `python face_controller.py --single-axis` (gas = left stick up, brake = left stick down) and map accelerate/brake to the left stick's vertical axis.
- **Games without controller support:** `python face_controller.py --keyboard` (arrow keys, Shift = nitro, Space = handbrake; steering and gas are pulsed so they stay analog).
- **Test without a game:** `python face_controller.py --dry-run` prints the values and presses nothing.

## Mac receiver (optional)

`mac/` is a small Mac app that presses keyboard keys instead (for Mac games) and serves a simple browser racing game for testing (`mac/game/yaris.html`). Its interface is in Turkish.

```
cd mac && ./build.sh          # puts "Yüz Direksiyon.app" on the Desktop
```

It needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility) to press keys. Run only one receiver at a time: the phone connects to the first one it finds.

## App settings

- **Gas:** Smile (default), Mouth (open your mouth) or Auto (always gas, puff cheeks to brake).
- **Steering:** Head tilt (default) or Head turn.
- **Sensitivity:** how many degrees of tilt give full steering lock (8°–35°).
- **Reverse:** flips the steering direction. **Center:** your current head pose becomes "straight".
- Tap the screen to hide the panel and see only your face.
- Face tracking needs some light: a desk lamp is enough, it doesn't work in total darkness.

## Privacy and safety

- The camera image never leaves the phone. Only the steering/gas/brake numbers are sent, and only on your local Wi-Fi.
- If no packet arrives for 0.3 s or your face is lost, the receiver centers the stick and releases everything.

---

## Türkçe

**Arabayı yüzünle sür.** iPhone'un Face ID kamerası gülümsemeni gaza, yanak şişirmeni frene, başını yatırmanı direksiyona çevirir; bilgisayar gerçek bir Xbox kolu takılı sanır.

▶️ Video: [NFS Underground 2'yi Sadece Yüzümle Oynadım](https://youtu.be/7qP2qAYkGS0)

**Kontroller:** gülümse = gaz (sağ tetik) · dudak büz / yanak şişir = fren, dururken geri (sol tetik) · başı sağa sola yatır = direksiyon (sol çubuk) · kaş kaldır = nitro (A) · tek göz kırp = el freni (B). Normal göz kırpma hiçbir şey yapmaz.

**Kurulum:**
1. Windows: `cd windows`, `pip install -r requirements.txt` (ViGEmBus sürücüsünün kurulumunu onayla), `python face_controller.py`. Güvenlik duvarı sorarsa **Özel ağlar**'a izin ver.
2. iPhone: `./generate.sh` (önce `brew install xcodegen`), `FaceController.xcodeproj`'u aç, takımını seç, telefonuna yükle. Ücretsiz Apple hesabı yeter.
3. Uygulamada düz bak, **Ortala**'ya dokun. Üstte **Bağlı: <bilgisayar adı>** görünmeli.
4. Oyunun kontrol ayarlarında kolu ata. Eski oyunlar için `--tek-eksen`, kol tanımayan oyunlar için `--klavye`, denemek için `--kuru`.

Need for Speed Underground 2 ile Windows'ta denendi. Mac alıcısı (`mac/`, Türkçe arayüz) klavye tuşlarına basar ve deneme için tarayıcıda basit bir yarış oyunu açar; Erişilebilirlik izni ister. Kamera görüntüsü telefondan çıkmaz, sadece direksiyon/gaz/fren değerleri ev ağında gider.

## License

MIT, see [LICENSE](LICENSE).
