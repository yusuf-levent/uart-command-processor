# UART Flight Controller

UART üzerinden gelen komutlarla uçuş durum makinesini (Flight FSM) kontrol eden Verilog HDL projesi.

## Kim Nereye Dosyalarını Açacak?

Çakışma olmaması için herkes **sadece kendi sorumlu olduğu dosyaları** açmalı ve düzenlemelidir:

| Kişi | Klasör | Açacağı Dosyalar | Açıklama |
| :--- | :--- | :--- | :--- |
| **Kişi 1 (Sen)** | `rtl/` | `baud_gen.v`, `cmd_fsm.v`, `flight_fsm.v`, `uart_top.v` | Baud üretici, komut + uçuş FSM'leri ve hepsini birleştiren ana modül |
| **Kişi 1 (Sen)** | `docs/diagrams/` | `cmd_fsm.png`, `flight_fsm.png` | Kendi çizdiğin FSM diyagramları (ve kök dizinde `README.md`, `.gitignore`) |
| **Kişi 2** | `rtl/` | `uart_tx.v` | TX (Gönderici) FSM modülü |
| **Kişi 2** | `docs/diagrams/` | `uart_tx.png` | TX FSM diyagramı (kendi denemek isterse `tb/` içine `tb_uart_tx.v`) |
| **Kişi 3** | `rtl/` | `uart_rx.v` | RX (Alıcı) FSM modülü |
| **Kişi 3** | `docs/diagrams/` | `uart_rx.png` | Çizdiği RX FSM diyagramı (kendi denemek isterse `tb/` içine `tb_uart_rx.v`) |
| **Kişi 4** | `tb/` | `tb_uart_top.v` | Ana testbench (send/receive, senaryolar, hata ve loopback testleri) |

## Port Tablosu (`uart_top`)

| Port | Yön | Genişlik | Açıklama |
| :--- | :--- | :--- | :--- |
| `clk` | input | 1 | Sistem saati (örn. 50 MHz / 100 MHz — *belirlenecek*) |
| `rst_n` | input | 1 | Aktif-düşük reset |
| `rx` | input | 1 | UART RX hattı |
| `tx` | output | 1 | UART TX hattı |

## Simülasyon Çalıştırma Komutları (Icarus Verilog)

```bash
# Ana sistem ve loopback simülasyonu (Kişi 4)
iverilog -o sim.vvp rtl/*.v tb/tb_uart_top.v
vvp sim.vvp
gtkwave dump.vcd

# RX modülü tekil testi (Kişi 3)
iverilog -o rx_sim.vvp rtl/baud_gen.v rtl/uart_rx.v tb/tb_uart_rx.v
vvp rx_sim.vvp

# TX modülü tekil testi (Kişi 2)
iverilog -o tx_sim.vvp rtl/baud_gen.v rtl/uart_tx.v tb/tb_uart_tx.v
vvp tx_sim.vvp
```
