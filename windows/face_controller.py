"""iPhone Face Controller, Windows receiver: turns the face values from the iPhone app into a virtual Xbox controller
(or keyboard keys). The game thinks a real controller is plugged in: steering and gas are fully analog.

The phone looks for _denemeyuz._udp on Bonjour; this program advertises that name (zeroconf). Packet format: iOS/FaceController/Protocol.swift.

Setup (once):   pip install -r requirements.txt     (zeroconf + vgamepad; vgamepad also installs the ViGEmBus driver)
Run:            python face_controller.py                 virtual Xbox controller
                python face_controller.py --single-axis   gas/brake on the left stick Y axis (old DirectInput games)
                python face_controller.py --keyboard      arrow keys, Shift, Space (games without controller support)
                python face_controller.py --dry-run       presses nothing, prints the values (test)
Controller mapping: left stick X = steering, right trigger = gas, left trigger = brake, A = nitro, B = handbrake.
  Old (DirectInput) games see the two Xbox triggers as ONE combined axis; --single-axis puts gas on left stick up and
  brake on left stick down, map "accelerate/brake" to the left stick's vertical axis in the game.
Safety: if no packet arrives for 0.3 s or the face is lost, the stick centers and everything is released. Ctrl+C to quit.
(TR) Türkçe bayraklar da çalışır: --tek-eksen, --klavye, --kuru. Mesajlar Windows Türkçeyse Türkçe çıkar.
"""
import json
import locale
import socket
import sys
import threading
import time

PORT = 47800
SERVIS = "_denemeyuz._udp.local."
KURU = "--kuru" in sys.argv or "--dry-run" in sys.argv
KLAVYE = "--klavye" in sys.argv or "--keyboard" in sys.argv
TEK_EKSEN = "--tek-eksen" in sys.argv or "--single-axis" in sys.argv
try:
    TR = (locale.getlocale()[0] or locale.getdefaultlocale()[0] or "").lower().startswith(("tr", "turkish"))
except Exception:
    TR = False

def L(tr, en):
    return tr if TR else en
AD = socket.gethostname()

# ---------- Çıkış: sanal Xbox kolu ----------
class Kol:
    def __init__(self):
        import vgamepad as vg
        self.vg = vg
        self.k = vg.VX360Gamepad()

    def yaz(self, d):
        x = max(-1.0, min(1.0, d["direksiyon"]))
        if TEK_EKSEN:
            # fren gazdan önceliklidir: ikisi birden varsa yalnız fren
            y = -d["fren"] if d["fren"] > 0.05 else d["gaz"]
            self.k.left_joystick_float(x_value_float=x, y_value_float=max(-1.0, min(1.0, y)))
            self.k.right_trigger_float(value_float=0.0)
            self.k.left_trigger_float(value_float=0.0)
        else:
            self.k.left_joystick_float(x_value_float=x, y_value_float=0.0)
            self.k.right_trigger_float(value_float=d["gaz"])
            self.k.left_trigger_float(value_float=d["fren"])
        B = self.vg.XUSB_BUTTON
        (self.k.press_button if d["nitro"] else self.k.release_button)(button=B.XUSB_GAMEPAD_A)
        (self.k.press_button if d["elFreni"] else self.k.release_button)(button=B.XUSB_GAMEPAD_B)
        self.k.update()

    def birak(self):
        self.k.reset(); self.k.update()

    def basili(self, d):
        return " ".join(x for x, v in [(L("Sol", "Left"), d["direksiyon"] < -0.05), (L("Sağ", "Right"), d["direksiyon"] > 0.05),
                                         (L("Gaz", "Gas"), d["gaz"] > 0.05), (L("Fren", "Brake"), d["fren"] > 0.05),
                                         ("A", d["nitro"]), ("B", d["elFreni"])] if v)

# ---------- Çıkış: klavye (DirectX oyunları için tarama kodu, SendInput) ----------
class Klavye:
    # (tarama kodu, genişletilmiş mi): ok tuşları genişletilmiş
    TUS = {"gaz": (0x48, True), "fren": (0x50, True), "sol": (0x4B, True), "sag": (0x4D, True),
           "nitro": (0x2A, False), "elFreni": (0x39, False)}
    AD = {"gaz": "↑", "fren": "↓", "sol": "←", "sag": "→", "nitro": "Shift", "elFreni": "Space"}

    def __init__(self):
        import ctypes
        from ctypes import wintypes
        self.ctypes = ctypes
        ULONG_PTR = ctypes.c_size_t

        class KEYBDINPUT(ctypes.Structure):
            _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                        ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]

        class MOUSEINPUT(ctypes.Structure):
            _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                        ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]

        class _U(ctypes.Union):
            _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]

        class INPUT(ctypes.Structure):
            _fields_ = [("type", wintypes.DWORD), ("u", _U)]

        self.KEYBDINPUT, self.INPUT = KEYBDINPUT, INPUT
        self.basilan = set()
        self.adim = 0

    def _gonder(self, ad, asagi):
        kod, genis = self.TUS[ad]
        bayrak = 0x0008 | (0x0001 if genis else 0) | (0 if asagi else 0x0002)   # SCANCODE | EXTENDED | KEYUP
        i = self.INPUT(type=1)
        i.u.ki = self.KEYBDINPUT(0, kod, bayrak, 0, 0)
        self.ctypes.windll.user32.SendInput(1, self.ctypes.byref(i), self.ctypes.sizeof(i))

    def yaz(self, d):
        # Kademeli: saniyede 10 tur; değer kadar basılı (yarım direksiyon = sürenin yarısı)
        self.adim = (self.adim + 1) % 10
        kademe = self.adim / 10

        def kad(v):
            return v > 0.05 and (v >= 0.9 or kademe < v)

        istenen = set()
        if d["fren"] > 0.4: istenen.add("fren")
        elif kad(d["gaz"]): istenen.add("gaz")
        if d["direksiyon"] < 0 and kad(-d["direksiyon"]): istenen.add("sol")
        if d["direksiyon"] > 0 and kad(d["direksiyon"]): istenen.add("sag")
        if d["nitro"]: istenen.add("nitro")
        if d["elFreni"]: istenen.add("elFreni")
        for t in self.basilan - istenen: self._gonder(t, False)
        for t in istenen - self.basilan: self._gonder(t, True)
        self.basilan = istenen

    def birak(self):
        for t in self.basilan: self._gonder(t, False)
        self.basilan = set()

    def basili(self, d):
        return " ".join(self.AD[t] for t in self.basilan)

class Kuru:
    def yaz(self, d): pass
    def birak(self): pass
    def basili(self, d):
        return f"steer {d['direksiyon']:+.2f} gas {d['gaz']:.2f} brake {d['fren']:.2f}"

# ---------- Ağ ----------
BOS = {"direksiyon": 0.0, "gaz": 0.0, "fren": 0.0, "nitro": False, "elFreni": False}
kilit = threading.Lock()
son = {"paket": None, "zaman": 0.0, "adres": None, "oturum": None, "sira": 0}

def dinle(sok):
    while True:
        veri, adres = sok.recvfrom(4096)
        try:
            p = json.loads(veri)
        except ValueError:
            continue
        with kilit:
            if p.get("oturum") != son["oturum"]:
                son["oturum"], son["sira"] = p.get("oturum"), 0
            if p.get("sira", 0) <= son["sira"]:
                continue        # geç gelen eski paket
            son.update(paket=p, zaman=time.time(), adres=adres, sira=p.get("sira", 0))

def yayinla():
    from zeroconf import ServiceInfo, Zeroconf
    ip = yerel_ip()
    bilgi = ServiceInfo(SERVIS, f"{AD}.{SERVIS}", addresses=[socket.inet_aton(ip)], port=PORT, server=f"{AD}.local.")
    z = Zeroconf()
    z.register_service(bilgi)
    return z, bilgi, ip

def yerel_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.1.1", 9))   # paket gitmez; yalnız hangi ağ kartının kullanılacağını öğrenir
        return s.getsockname()[0]
    finally:
        s.close()

def main():
    cikis = Kuru() if KURU else (Klavye() if KLAVYE else Kol())
    sok = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sok.bind(("0.0.0.0", PORT))
    threading.Thread(target=dinle, args=(sok,), daemon=True).start()
    z, bilgi, ip = yayinla()
    mod = (L("kuru", "dry run") if KURU else (L("klavye", "keyboard") if KLAVYE else
           (L("sanal Xbox kolu, gaz/fren sol çubukta", "virtual Xbox controller, gas/brake on the left stick") if TEK_EKSEN
            else L("sanal Xbox kolu", "virtual Xbox controller"))))
    print(L(f"Yüz Direksiyon hazır: {AD} ({ip}:{PORT}), çıkış: {mod}. Telefonda uygulamayı aç, düz bak, Ortala. Çıkmak: Ctrl+C",
            f"Face Controller ready: {AD} ({ip}:{PORT}), output: {mod}. Open the app on the iPhone, look straight, tap Center. Quit: Ctrl+C"))
    son_cevap = son_yazi = 0.0
    try:
        while True:
            simdi = time.time()
            with kilit:
                p, zaman, adres = son["paket"], son["zaman"], son["adres"]
            canli = p is not None and simdi - zaman < 0.3 and p.get("takip")
            d = {k: p.get(k, v) for k, v in BOS.items()} if canli else BOS
            if canli:
                cikis.yaz(d)
            else:
                cikis.birak()
            if adres and simdi - son_cevap > 0.2:
                son_cevap = simdi
                cevap = {"ad": AD, "acik": True, "izin": True, "tuslar": cikis.basili(d) if canli else ""}
                sok.sendto(json.dumps(cevap).encode(), adres)
            if simdi - son_yazi > 0.5:
                son_yazi = simdi
                durum = ((L("yüz var  ", "face  ") + cikis.basili(d)) if canli else
                         (L("telefon bağlı, yüz yok", "phone connected, no face") if p and simdi - zaman < 1.5 else L("telefon bekleniyor", "waiting for the phone")))
                print(f"\r{durum:<60}", end="", flush=True)
            time.sleep(0.01)
    except KeyboardInterrupt:
        pass
    finally:
        cikis.birak()
        z.unregister_service(bilgi)
        z.close()
        print(L("\nKapandı, kol ortalandı.", "\nStopped, controller centered."))

if __name__ == "__main__":
    main()
