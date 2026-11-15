# CONFIG FREEZE - Parameter Teroptimasi PQ-IKEv2 (Tahap 4)

- **Peneliti:** Rafi Rachman (NIM 2407187)
- **Tanggal Penetapan (Freeze):** 2026-11-14 12:57:19
- **Sumber Data Pilot/Tuning:** C:\Users\<USER>\Documents\pq-ikev2\03_pilot\uji-20261114-1219
- **Mekanisme Penerapan:** /etc/strongswan.d/zz-eksperimen.conf (blok charon { ... }) di kedua VM, diikuti systemctl restart strongswan dan swanctl --load-all.
- **Status Konfigurasi:** **TERKUNCI (FROZEN)** - Parameter di bawah ini digunakan secara tetap untuk seluruh 81 skenario evaluasi utama (Tahap 5) tanpa perubahan.

## 1. Tabel Parameter Terkunci (Sesuai Tabel 3.8 Proposal)

| Parameter (strongSwan/charon) | Klasik (Baseline) | Hybrid Default | Hybrid Teroptimasi (FROZEN) | Hybrid +A (Ablation) | Hybrid +B (Ablation) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Proposal Key Exchange** | x25519 | x25519-ke1_mlkem768 | x25519-ke1_mlkem768 | x25519-ke1_mlkem768 | x25519-ke1_mlkem768 |
| **charon.fragment_size** | 1280 | 1280 | **Adaptif MTU - 28 (1252 / 1372 / 1472)** | MTU - 28 | 1280 |
| **charon.retransmit_timeout** | 4.0 s | 4.0 s | **3.0 s** (dari cand-t3.0-r3) | 4.0 s | 3.0 s |
| **charon.retransmit_tries** | 5 | 5 | **3** (dari cand-t3.0-r3) | 5 | 3 |
| **Metode Autentikasi** | PSK | PSK | PSK | PSK | PSK |

## 2. Bukti Fragmentasi & Hasil Pengujian Pilot/Tuning (dengan Bootstrap 95% CI untuk p95)

| No | Kondisi (MTU_Loss_RTT) | Konfigurasi | Run Valid | Success Rate | Median (ms) | p95 (ms) | Bootstrap 95% CI p95 (ms) | Rata-rata Retransmisi | Rata-rata Bytes | Paket Fragmen IKE | CPU Init | Status QC |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | MTU1280_loss5_rtt100 | hybrid-default | 20/20 | 100% | 2329 | 4332.4 | [4325.3, 4340] (lebar 14.7) | 0.55 | 4268 | 42 | 0.18s | OK |
| 2 | MTU1500_loss0_rtt10 | hybrid-default | 20/20 | 100% | 51.5 | 61.05 | [54.1, 62] (lebar 7.9) | 0 | 4160 | 40 | 0.16s | OK |
| 3 | MTU1280_loss5_rtt100 | hybrid-optimized | 20/20 | 100% | 324 | 3333.55 | [354, 3344] (lebar 2990) | 0.3 | 4224 | 41 | 0.19s | OK |
| 4 | MTU1280_loss5_rtt100 | klasik | 20/20 | 100% | 223 | 4219.05 | [234, 4239] (lebar 4005) | 0.35 | 1574 | 0 | 0.18s | OK |
| 5 | MTU1500_loss0_rtt10 | klasik | 20/20 | 100% | 46 | 76.95 | [55.1, 95] (lebar 39.9) | 0 | 1523 | 0 | 0.19s | OK |
| 6 | MTU1500_loss0_rtt10 | hybrid-optimized | 20/20 | 100% | 55 | 78.4 | [65.1, 105] (lebar 39.9) | 0 | 4049 | 0 | 0.18s | OK |

## 3. Estimasi Durasi Eksperimen Utama (81 Skenario x 100 Run = 8.100 Run)

- **Kisaran Estimasi Total Waktu:** **3.17 jam s.d. 5.25 jam** (maksimum 7.55 jam; feasible diselesaikan dalam jadwal penelitian dengan fitur resume -Nama).
- **Kriteria Lolos Tahap 4:**
  1. Fragmentasi IKE teramati secara empiris pada berkas .pcap (Encrypted Fragment RFC 7383): **TERPENUHI** (lihat bukti-fragmentasi.txt).
  2. Parameter teroptimasi dipilih berdasarkan trade-off success rate, handshake time (median & p95 Bootstrap CI), retransmisi, dan overhead: **TERPENUHI (cand-t3.0-r3)**.
  3. Estimasi waktu total feasible: **TERPENUHI**.
  4. Skrip otomatisasi & QC lolos uji tanpa intervensi manual: **TERPENUHI**.