# UART + Komut Yorumlayıcı Projesi (Verilog, FSM)

Computer Architecture dersi dönem projesi · 4 kişilik grup · Sunum: 18 Aralık 2026

---

# BÖLÜM A: Proje 11 (Faz 1)

## 1) UART nedir? (haberleşme bilgisi sıfırsa bile yeter)

İki cihaz arasında **iki tel** var: biri gönderme (TX), biri alma (RX). Ortak saat yok, ikisi de aynı hızı (baud rate) önceden biliyor. Veri **bayt bayt** ve sırayla bit bit gidiyor.

Hat boşken **1** durumunda. Bir bayt şöyle gider:

```
boşta(1) → START(0) → 8 veri biti (önce en düşük bit) → PARITY → STOP(1) → boşta(1)
```

Örnek: 'A' karakteri (0x41 = 01000001). Önce en düşük bit gönderildiği için hatta şu görünür: `0 | 1 0 0 0 0 0 1 0 | 0 | 1` (start, 8 bit, parity, stop). Parity bitini şöyle hesaplıyoruz (even parity): toplam 1 sayısı çift olsun. 'A'da iki tane 1 var, zaten çift, parity=0. Bir bit süresi sabit, yani bir bayt 11 bit süresi sürüyor.

**Alıcı tarafın asıl işi:** Saat ortak olmadığı için bitin **tam ortasında** okuması lazım. Hat 1'den 0'a düşünce start geldiğini anlıyor, yarım bit bekliyor, hâlâ 0'sa gerçek start bu, sonra her bit süresinde bir örnek alıyor.

**Öğrenme maliyeti:** Gerçekçi tahmin 2-3 saat. Voltaj seviyeleri, RS-232 gibi donanım detayları bizi ilgilendirmiyor, sadece mantıksal protokol var. İlk hafta herkes bu bölümü okuyup frame'i elle çizsin ("UART 8E1 frame" diye aramak yeter), gerisini yazarken öğrenirsiniz. Haberleşme bilgisi sıfır olmak burada sorun değil.

## 2) Sistem tam olarak ne yapıyor?

Gerçek bilgisayar ya da kart yok. Testbench "bilgisayarı" taklit ediyor ve tasarımınıza harf gönderiyor, tasarım da karşılık veriyor:

```
Testbench ("PC")                       Sizin tasarımınız
  rx hattı ───────────► [uart_rx] ─► [cmd_fsm] ─► LED register, sayaç
  tx hattı ◄─────────── [uart_tx] ◄─────┘
                [baud_gen] ──► uart_tx, uart_rx
```

**Komut protokolü (Faz 1):**

| Gelen | Yapılan | Cevap |
|---|---|---|
| 'A' | LED aç | 'K' (tamam) |
| 'B' | LED kapat | 'K' |
| 'S' | Sayacı başlat | 'K' |
| 'P' | Sayacı durdur | 'K' |
| 'R' | Sayacı sıfırla | 'K' |
| 'Q' | Sayaç değerini sor | sayaç değeri (1 bayt) |
| başka karakter ya da parity/frame hatası | hiçbir şey yapma | 'E' (hata) |

**Modüller:**

- **baud_gen:** Clock'u bölüp bit hızının 16 katında bir darbe (`tick16`) üretir. Gerçek kartta 50 MHz ve 115200 baud için bölme sayısı yaklaşık 27 (50e6 / (16 × 115200)). Simülasyonda küçük bir sayı (2-4) kullanırız ki simülasyon hızlı olsun.
- **uart_tx:** Bir baytı frame'e çevirip hatta gönderir.
- **uart_rx:** Hattan frame'i okuyup baytı çıkarır, parity ve stop bitini kontrol eder.
- **cmd_fsm:** Gelen baytı yorumlar, LED/sayaca uygular, cevabı gönderir.
- **peripherals:** 1 bitlik LED register'ı ve 8 bitlik sayaç.
- **uart_top:** Hepsini bağlar.

## 3) FSM'ler

**uart_tx (5 durum):**

| Durum | Hat | Sonraki durum |
|---|---|---|
| IDLE | 1 | `tx_start` gelince baytı kaydet → START |
| START | 0 | 1 bit süresi (16 tick) dolunca → DATA |
| DATA | veri[bit_no] | Her bit süresinde bit_no artar, 8. bitten sonra → PARITY |
| PARITY | parity biti | Bit süresi dolunca → STOP |
| STOP | 1 | Bit süresi dolunca → IDLE (`tx_done` darbesi) |

`tx_busy` = IDLE dışında her durumda 1.

**uart_rx (5 durum):**

| Durum | Ne yapar | Sonraki durum |
|---|---|---|
| IDLE | Hat 0'a düşmesini bekler | → START |
| START | 8 tick bekler (bitin ortası), hat hâlâ 0 mı bakar | 0 ise → DATA, 1 ise (parazit) → IDLE |
| DATA | Her 16 tick'te bir örnek alır, 8 bit toplar | → PARITY |
| PARITY | Örnek alır, hesaplananla karşılaştırır (`parity_err`) | → STOP |
| STOP | Örnek alır, 1 olmalı (değilse `frame_err`) | → IDLE, `rx_valid` darbesi |

**cmd_fsm (4 durum):** IDLE (`rx_valid` bekler) → DECODE (harf ne?) → EXECUTE (LED/sayaç işlemi) → RESPOND (`tx_busy` düşünce cevap baytını verir, `tx_done`'u bekler) → IDLE. Hata varsa DECODE'dan doğrudan 'E' cevabına gider.

## 4) Testbench (bu projenin en önemli kısımlarından biri)

Testbench'te **tasarımdan bağımsız** iki yardımcı yazılır: bir `send_byte` görevi (rx hattını `#gecikme` ile elle sürer) ve bir `receive_monitor` (tx hattını dinleyip baytı toplar). Bağımsız olması önemli, çünkü aynı kişinin yanlış anladığı şeyi hem tasarım hem test tekrar etmesin.

Senaryolar: her komut ('A'..'Q'), bilinmeyen harf, hatalı parity, hatalı stop bit, arka arkaya baytlar, reset, bir de tx'i rx'e bağlayan **loopback testi** (rastgele baytlar gönder, aynısı gelmeli). Çıktı olarak waveform + konsolda `PC → 'A' | DUT → 'K' | PASS` gibi satırlar.

## 5) Kim ne yapacak

Baud_gen çok hafif, cmd_fsm ile testbench ise ağır olduğu için dağılım şöyle:

- **Kişi 1 (lider):** baud_gen, cmd_fsm, uart_top, entegrasyon. Anlatacağı: mimari, komut protokolü, cmd FSM diyagramı.
- **Kişi 2:** uart_tx (FSM), parity üretimi. Anlatacağı: frame formatı, TX FSM, bit zamanlaması.
- **Kişi 3:** uart_rx (FSM), start doğrulama, orta örnekleme, hata bayrakları. Anlatacağı: neden bitin ortasından örnekliyoruz, RX FSM. Bu en zor modül.
- **Kişi 4:** Testbench (bağımsız send/receive modelleri, senaryolar, loopback), peripherals (LED, sayaç). Anlatacağı: test stratejisi, waveform okuma.

## 6) Basit mi kaçar?

Dürüst cevap: **Faz 1 tek başına biraz basit kalır.** Deneyimli biri için TX ve RX birer-iki günlük iş, sıfırdan öğrenen bir grup için testbench dahil 4-5 hafta, yani zorluk "Orta". Elinizde 10 hafta var, o yüzden Faz 1'i çekirdek olarak alıp üstüne ekleyin. İyi tarafı: sunumda tek bir baytın frame'ini waveform'da göstermek (start, 8 bit, parity, stop) çok net ve etkileyici durur, bir de zamanlama hataları (bir bit kayması) debug'ı zorlaştırır, yani göründüğü kadar kolay da değil.

**Faz 2 (6-8. hafta), sırayla:** 8 derinlikli RX/TX FIFO (arka arkaya gelen baytlar kaybolmasın), iki baytlı komutlar ('L' + rakam) ve zaman aşımı (argüman gelmezse vazgeç), hata sayacı ve sorgu komutu, **paket + CRC** (paket başlığı, uzunluk, veri, CRC; alıcı CRC'yi doğrular, hatalıyı reddeder). Son madde zaten 12. proje, yani 12'ye geçiş doğal bir devam, baştan başlamanıza gerek yok.

## 7) Hafta hafta (Faz 1 ve genel takvim)

| Hafta | Ne |
|---|---|
| 1 (8-14 Eki) | Herkes UART'ı öğrenir, ısınma FSM'i, port listesi ve komut tablosu dondurulur |
| 2 (15-21) | baud_gen, TX ilk hali, RX iskeleti, testbench'te send/receive |
| 3 (22-28) | RX tamam, TX+RX loopback testi geçer, cmd_fsm yazılır |
| 4 (29 Eki-4 Kas) | Parity/frame hata testleri, cmd_fsm tek başına testi, peripherals |
| 5 (5-11 Kas) | Birleştirme, tüm komutlar testbench'ten çalışıyor. **Karar noktası:** rahatsanız Faz 2'ye geçin |
| 6-8 (12 Kas-2 Ara) | FIFO, iki baytlı komut, hata sayacı, istenirse paket + CRC |
| 9 (3-9 Ara) | Cila, köşe durumları, sunum notları |
| 10 (10-16 Ara) | İngilizce prova |

---

# BÖLÜM B: Faz 2 (12. Proje) Görev Dağılımı ve Zaman Çizelgesi

12. proje ayrı bir proje değil, **11'in üstüne eklenen üç katman.** Yaptığınız UART TX/RX ve komut yorumlayıcı 12'nin alt yarısı, yani 11'i bitirince hiçbir şey çöpe gitmiyor.

## 11'de ne var, ne yok

Gönderici, alıcı ve gelen harfi yorumlayan bir FSM var. Depolama yok, sadece LED ve sayaç gibi küçük register'lar var. Alıcı bir bayt alır, hemen işler. Bu yüzden iki sorun çıkar:

1. Bir bayt işlenirken ya da cevap gönderilirken (yaklaşık 11 bit süresi) arkasından başka bayt gelirse **kaybolur**.
2. Alıcı mesajın nerede başlayıp bittiğini bilmez ve **hatayı yakalayamaz** (parity sadece tek bitlik hatayı yakalar).

12'nin eklediği üç şey bu iki sorunu çözüyor.

## 12'nin eklediği üç şey

### 1) FIFO (depolama dediğin şey bu)

Küçük bir kuyruk: 8 baytlık bir bellek dizisi, bir yazma göstergesi, bir okuma göstergesi, "dolu" ve "boş" bayrakları. UART bayt alınca kuyruğa koyar, komut yorumlayıcı hazır olunca sırayla alır. Böylece arka arkaya gelen baytlar kaybolmaz. Zorluğu düşük, bir hafta sürmez.

### 2) Paket

Tek harf yerine yapılandırılmış mesaj gider:

```
[BAŞLANGIÇ 0x7E] [UZUNLUK] [VERİ ...] [CRC]
```

"LED aç" artık 'A' değil, `7E 01 41 CRC` paketi. Alıcıda paketi okuyan yeni bir FSM var: BAŞLANGIÇ'ı bekle → UZUNLUK'u oku → o kadar VERİ baytı oku → CRC'yi oku → kontrol et. Mesajın nerede başlayıp bittiği belli oluyor.

### 3) CRC

Verinin bir tür "imzası". Gönderen veriden hesaplayıp pakete ekler, alıcı kendi hesaplar, tutmuyorsa paketi reddeder ve hata cevabı döner. Donanımda küçük bir kaydırma yazmacıyla yapılır (bir bayt için 8 adım). Testbench'te paketin bir bitini bilerek bozup CRC'nin yakaladığını göstermek sunumun güzel anı olur.

## Mimari

```
Gönderen: komut → [tx_packetizer + CRC] → [tx_fifo] → [uart_tx] ──►
Alıcı:    ──► [uart_rx] → [rx_fifo] → [rx_parser + CRC kontrol] → cmd_fsm
```

11'deki uart_tx, uart_rx ve komutlar aynen kalıyor, etraflarına katman ekleniyor.

## Faz 2'de kim ne yapar (11'deki rollerin devamı)

- **Kişi 2:** tx_fifo + tx_packetizer (paketi kurar, CRC'yi ekler)
- **Kişi 3:** rx_fifo + rx_parser (paket ayrıştırma FSM'i)
- **Kişi 1:** crc modülü, cmd_fsm'in paket sürümü, top module
- **Kişi 4:** Yeni testler (bit bozma, kısa paket, yanlış uzunluk, arka arkaya paketler)

## Faz 2 zaman çizelgesi

Süre olarak FIFO yaklaşık 1 hafta, parser FSM 1-1.5 hafta, CRC 3-4 gün, yani Faz 2 toplam 3 hafta civarı. Takvimdeki 6-8. haftalara denk geliyor.

| Hafta | Ne |
|---|---|
| 6 (12-18 Kas) | rx_fifo ve tx_fifo, FIFO testleri (doluluk, boşluk, arka arkaya baytlar) |
| 7 (19-25 Kas) | Paket formatı, tx_packetizer ve rx_parser FSM'i |
| 8 (26 Kas-2 Ara) | CRC modülü, entegrasyon, bit bozma ve kısa paket testleri |

## Öneri

Sırayı **FIFO → paket → CRC** tutun. Her adım kendi başına tamam bir özellik, yani yarıda kalsanız bile sunumda "FIFO ekledik" ya da "paket formatı ekledik" diyebilirsiniz, tamamı olmak zorunda değil. Karar noktası yine 5. hafta sonu: 11 temiz çalışıyorsa Faz 2'ye geçin.
