# Sahte telefon: Yüz Direksiyon'a N saniye boyunca sabit yüz değerleri yollar. Kullanım: python3 sahte_yuz.py PORT SANIYE
import socket, json, time, sys
p = int(sys.argv[1]); n = float(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
i = 0; bas = time.time()
while time.time() - bas < n:
    i += 1
    s.sendto(json.dumps(dict(oturum=5, sira=i, takip=True, direksiyon=-0.6, gaz=1.0, fren=0, nitro=True, elFreni=False)).encode(), ("127.0.0.1", p))
    time.sleep(1 / 60)
