# UART Flight Controller (İHA Uçuş Kontrolcüsü)

UART (8E1 — 115200 baud, 50 MHz) üzerinden gelen komutlarla bir İHA'nın uçuş durum makinesini (`flight_fsm`) yöneten, Faz 2 ile birlikte **FIFO + Paket Protokolü + CRC-8** katmanlarıyla genişletilen Verilog HDL projesidir.

---

## Sistem Mimarisi

### Faz 1 (Tamamlandı — 15/15 PASS)
```text
rx ──► [uart_rx] ──► [cmd_fsm] ──► [flight_fsm]
tx ◄── [uart_tx] ◄───────┘
          ▲
     [baud_gen] (tick16, DIVISOR = 27)
```

### Faz 2 (FIFO + Paket + CRC-8)
```text
rx ──► [uart_rx] ──► [u_rx_fifo (fifo)] ──► [rx_parser + crc8] ──► [cmd_fsm] ──► [flight_fsm]
tx ◄── [uart_tx] ◄── [u_tx_fifo (fifo)] ◄── [tx_packetizer + crc8] ◄──┘
```

---

## İHA Uçuş Komutları ve Durum Geçişleri

Başlangıç (reset) durumu: **`DISARMED`**. Geçerli geçişte cevap **`'K'` (`0x4B`)**, geçersiz komut/durum veya hat/CRC hatasında cevap **`'E'` (`0x45`)** döner.

| Mevcut Durum | Komut (ASCII) | Hex | Yeni Durum | Cevap |
| :--- | :--- | :--- | :--- | :--- |
| `DISARMED` | `'A'` (Arm) | `0x41` | `ARMED` | `'K'` |
| `ARMED` | `'D'` (Disarm) | `0x44` | `DISARMED` | `'K'` |
| `ARMED` | `'T'` (Takeoff / Flight) | `0x54` | `FLIGHT` | `'K'` |
| `FLIGHT` | `'L'` (Landing) | `0x4C` | `LANDING` | `'K'` |
| `FLIGHT` | `'F'` (Failsafe) | `0x46` | `FAILSAFE` | `'K'` |
| `LANDING` | `'D'` (Disarm) | `0x44` | `DISARMED` | `'K'` |
| `LANDING` | `'F'` (Failsafe) | `0x46` | `FAILSAFE` | `'K'` |
| `FAILSAFE` | `'D'` veya `'R'` (Reset) | `0x44` / `0x52` | `DISARMED` | `'K'` |
| *Diğer tüm durum/komutlar* | — | — | *Değişmez* | `'E'` |

---

## Ekip Görev Dağılımı (Kim Hangi Dosyadan Sorumlu?)

Çakışma olmaması için herkes **sadece kendi sorumlu olduğu dosyaları** açmalı ve düzenlemelidir:

### Faz 1 Dosyaları (Tamamlandı)
| Kişi | Klasör | Dosyalar | Açıklama |
| :--- | :--- | :--- | :--- |
| **Kişi 1 (Lider)** | `rtl/` | `baud_gen.v`, `cmd_fsm.v`, `flight_fsm.v`, `uart_top.v` | Baud üreteci, komut + uçuş FSM'leri ve ana bağlantı modülü |
| **Kişi 1 (Lider)** | `docs/diagrams/` | `cmd_fsm.png`, `flight_fsm.png` | FSM diyagramları (ve kök dizinde `README.md`, `.gitignore`) |
| **Kişi 2** | `rtl/`, `docs/diagrams/` | `uart_tx.v`, `tx_diagram.jpg` | TX (Gönderici) FSM modülü ve diyagramı |
| **Kişi 3** | `rtl/`, `docs/diagrams/` | `uart_rx.v`, `uart_rx.png` | RX (Alıcı) FSM modülü ve diyagramı |
| **Kişi 4** | `tb/` | `tb_uart_top.v` | Ana sistem, hata enjeksiyonu ve loopback testbenchi |

### Faz 2 Dosyaları (FIFO + Paket + CRC-8 — Seçenek A)
| Kişi | Klasör | Açacağı / Güncelleyeceği Dosyalar | Açıklama |
| :--- | :--- | :--- | :--- |
| **Kişi 1 (Lider)** | `rtl/` | `crc8.v`, `cmd_fsm.v` *(güncelleme)*, `uart_top.v` *(güncelleme)* | Ortak CRC-8 modülü, `pkt_len == 1` destekli `cmd_fsm` ve Faz 2 üst modül entegrasyonu |
| **Kişi 2** | `rtl/` | `fifo.v`, `tx_packetizer.v` | Tek ortak 8×8 FIFO (`uart_top`'ta RX ve TX için 2 kere kullanılır) + cevap paketleyici (`[0x7E][LEN][DATA][CRC8]`) |
| **Kişi 3** | `rtl/` | `rx_parser.v` | Paket ayrıştırıcı + CRC/uzunluk/timeout/`rx_err` doğrulayıcı FSM |
| **Kişi 4** | `tb/` | `tb_fifo.v`, `tb_uart_top.v` *(güncelleme)* | FIFO tekil testi + Faz 2 paket, CRC bit bozma, kısa paket, yanlış uzunluk, arka arkaya paket ve orta yerde reset testleri |

---

## Faz 2 Donmuş Protokol ve Arayüz Sözleşmesi

Tüm iç modüller `posedge clk` senkron ve **aktif-yüksek `rst`** kullanır (`uart_top` dış portu `rst_n` olup içeride `rst = ~rst_n` üretilir).

### 1. Paket Formatı
```text
[START = 0x7E] [LEN] [DATA_0 ... DATA_{LEN-1}] [CRC8]
```
- **START:** `8'h7E`
- **LEN:** `1..4` arası geçerli (`LEN == 0` veya `LEN > 4` ise paket hatası `pkt_err = 1`). İHA komutları ve cevapları `LEN = 1` kullanır (toplam 4 bayt).
- **CRC-8 Standardı:** **CRC-8/SMBUS** — Polinom `8'h07`, başlangıç `8'h00`, yansıtma yok, final XOR yok. Sadece **`LEN` ve `DATA`** baytları üzerinden hesaplanır (`0x7E` dahil değildir).
- **Yarım/Kısa Paket Timeout'u:** `TIMEOUT_TICKS = 384` (`tick16` cinsinden 24 bit süresi ≈ 2 bayt).

**Doğrulanmış Referans Paketler (Hex):**
| Anlam | Paket (Hex) |
| :--- | :--- |
| Arm (`'A'`) | `7E 01 41 D5` |
| Disarm (`'D'`) | `7E 01 44 CE` |
| Takeoff / Flight (`'T'`) | `7E 01 54 BE` |
| Landing (`'L'`) | `7E 01 4C F6` |
| Failsafe (`'F'`) | `7E 01 46 C0` |
| Reset (`'R'`) | `7E 01 52 AC` |
| Cevap OK (`'K'`) | `7E 01 4B E3` |
| Cevap Hata (`'E'`) | `7E 01 45 C9` |

### 2. Modül Portları (Faz 2)

- **Ortak FIFO (`fifo` — 8 derinlik × 8 bit, FWFT `assign rd_data = mem[rd_ptr];`):**
  `clk`, `rst`, `wr_en`, `wr_data[7:0]`, `rd_en`, `rd_data[7:0]`, `full`, `empty`
- **CRC-8 (`crc8` — 1 clock'ta tek bayt günceller):**
  `clk`, `rst`, `crc_init`, `crc_en`, `data_in[7:0]`, `crc_out[7:0]`
- **RX Parser (`rx_parser`):**
  `clk`, `rst`, `tick16`, `rx_err`, `fifo_data[7:0]`, `fifo_empty`, `fifo_rd_en`, `pkt_cmd[7:0]`, `pkt_len[7:0]`, `pkt_valid`, `pkt_err`
- **TX Packetizer (`tx_packetizer`):**
  `clk`, `rst`, `pkt_start`, `pkt_data[7:0]`, `pkt_busy`, `fifo_full`, `fifo_wr_en`, `fifo_wr_data[7:0]`

---

## Port Tablosu (`uart_top`)

| Port | Yön | Genişlik | Açıklama |
| :--- | :--- | :--- | :--- |
| `clk` | input | 1 | Sistem saati (`CLK_FREQ = 50_000_000`) |
| `rst_n` | input | 1 | Aktif-düşük dış reset |
| `rx` | input | 1 | UART 8E1 RX hattı (`BAUD_RATE = 115200`) |
| `tx` | output | 1 | UART 8E1 TX hattı (`BAUD_RATE = 115200`) |

---

## Simülasyon Çalıştırma Komutları (Icarus Verilog)

```bash
# Gerçek sistem testi (uart_top + tüm RTL modülleri)
iverilog -g2012 -DUSE_DUT -o sim.vvp rtl/*.v tb/tb_uart_top.v
vvp sim.vvp

# Sadece testbench öz-testi (loopback)
iverilog -g2012 -o loop.vvp tb/tb_uart_top.v
vvp loop.vvp

# Dalga formunu görüntüleme
gtkwave dump.vcd
```
