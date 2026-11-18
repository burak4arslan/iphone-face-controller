# Yüz Direksiyon — Windows

Telefondaki Denemeler › **Yüzle sür** yüz hareketlerini Wi-Fi'dan yollar; bu program onları **sanal Xbox koluna** çevirir.
Oyun gerçek bir kol takılı sanır: direksiyon ve gaz tam kademeli (analog), tuş basılı kalma sorunu yok.

## Kurulum (bir kez)
1. Python 3 kur (python.org, kurulumda **"Add python.exe to PATH"** kutusunu işaretle).
2. Komut istemi: `pip install zeroconf vgamepad`
   - vgamepad, sanal kol sürücüsü **ViGEmBus**'ı da kurar; çıkan kurulum penceresini onayla.
3. Bu klasörü (`yuz_direksiyon.py`) Windows'a kopyala.

## Kullanım
1. **Mac'teki "Yüz Direksiyon" uygulamasını kapat.** İkisi aynı anda açıksa telefon ilk bulduğuna bağlanır.
2. Windows'ta: `python yuz_direksiyon.py`
   - Güvenlik duvarı sorarsa **Özel ağlar**'a izin ver (yoksa telefon bulamaz).
3. Telefonda Yüzle sür → düz bak → **Ortala**. Üstte "Bağlı: <bilgisayar adı>" görünmeli.
4. Oyunun kontrol ayarlarında kolu ata:
   - Sol çubuk sağ/sol = **direksiyon**
   - Sağ tetik = **gaz**, sol tetik = **fren**
   - A = **nitro** (kaş), B = **el freni** (tek göz)

Kolu tanımayan oyunlarda: `python yuz_direksiyon.py --klavye` (ok tuşları, Shift, Boşluk).
Denemek için hiçbir şey basmadan: `python yuz_direksiyon.py --kuru`.

Güvenlik: 0,3 sn telefon verisi gelmezse ya da yüz kaybolursa kol ortalanır, gaz bırakılır. Çıkmak: Ctrl+C.

## NFS 2 gibi eski oyunlar
Eski oyunlar Xbox kolunu DirectInput ile görür ve iki tetiği **tek eksende birleştirir**: gaz ve fren ayrı atanamaz,
ikisine birden basınca sıfırlanır (bilinen bir Windows davranışı). O yüzden:

1. Önce `python yuz_direksiyon.py --tek-eksen` ile dene. Gaz = sol çubuk yukarı, fren = sol çubuk aşağı.
   Oyunun kontrol ayarlarında direksiyonu sol çubuğun yatay eksenine, gaz/freni dikey eksenine ata
   (atarken telefonda başını eğ / gülümse ki oyun hareketi algılasın).
2. Oyun kolu hiç tanımazsa: `python yuz_direksiyon.py --klavye` (ok tuşları; direksiyon ve gaz kademeli basılır).

NFS 2 SE'de bu yolların hangisinin çalıştığını kimse denemedi; bu bilgi genel Windows/DirectInput davranışından.
Windows'ta henüz hiç çalıştırılmadı; Mac'te yalnız `--kuru` modunda denendi.
