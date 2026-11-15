# CONFIG FREEZE — Parameter Teroptimasi PQ-IKEv2 (Tahap 4)

- **Peneliti:** Rafi Rachman (NIM 2407187)
- **Tanggal Penetapan (Freeze):** 2026-11-14 13:53:55
- **Sumber Data Pilot/Tuning:** C:\Users\<USER>\Documents\pq-ikev2\03_pilot\tuning-20261114-1258
- **Mekanisme Penerapan:** /etc/strongswan.d/zz-eksperimen.conf (blok charon { ... }) di kedua VM, diikuti systemctl restart strongswan dan swanctl --load-all.
- **Status Konfigurasi:** **TERKUNCI (FROZEN)** — Parameter di bawah ini digunakan secara tetap untuk seluruh 81 skenario evaluasi utama (Tahap 5) tanpa perubahan.

## 1. Tabel Parameter Terkunci (Sesuai Tabel 3.8 Proposal)

| Parameter (strongSwan/charon) | Klasik (Baseline) | Hybrid Default | Hybrid Teroptimasi (FROZEN) | Hybrid +A (Ablation) | Hybrid +B (Ablation) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Proposal Key Exchange** | x25519 | x25519-ke1_mlkem768 | x25519-ke1_mlkem768 | x25519-ke1_mlkem768 | x25519-ke1_mlkem768 |
| **charon.fragment_size** | 1280 | 1280 | **Adaptif MTU - 28 (1252 / 1372 / 1472)** | MTU - 28 | 1280 |
| **charon.retransmit_timeout** | 4.0 s | 4.0 s | **2.0 s** (dari cand-t2.0-r3) | 4.0 s | 2.0 s |
| **charon.retransmit_tries** | 5 | 5 | **3** (dari cand-t2.0-r3) | 5 | 3 |
| **Metode Autentikasi** | PSK | PSK | PSK | PSK | PSK |

## 2. Bukti Fragmentasi & Hasil Pengujian Pilot/Tuning (dengan Bootstrap 95% CI untuk p95)

| No | Kondisi (MTU_Loss_RTT) | Konfigurasi | Run Valid | Success Rate | Median (ms) | p95 (ms) | Bootstrap 95% CI p95 (ms) | Rata-rata Retransmisi | Rata-rata Bytes | Paket Fragmen IKE | CPU Init | Status QC |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | MTU1280_loss1_rtt50 | cand-t3.0-r4 | 40/40 | 100% | 172 | 176.25 | [174, 183] (lebar 9) | 0 | 4160 | 80 | 0.31s | OK |
| 2 | MTU1500_loss5_rtt50 | cand-t2.0-r3 | 40/40 | 100% | 175 | 2176 | [2171, 2182] (lebar 11) | 0.22 | 4069 | 0 | 0.37s | OK |
| 3 | MTU1280_loss1_rtt50 | cand-t3.0-r3 | 40/40 | 100% | 172 | 3169.15 | [175.6, 3176] (lebar 3000.4) | 0.08 | 4227 | 83 | 0.32s | OK |
| 4 | MTU1280_loss5_rtt100 | cand-t3.0-r3 | 100/100 | 100% | 322 | 6321.1 | [3323, 6444.8] (lebar 3121.8) | 0.34 | 4332 | 217 | 0.8s | OK |
| 5 | MTU1400_loss5_rtt100 | cand-t2.0-r3 | 40/40 | 100% | 321 | 2511.95 | [2323.15, 7923] (lebar 5599.85) | 0.28 | 4140 | 0 | 0.35s | OK |
| 6 | MTU1280_loss1_rtt50 | hybrid-default | 40/40 | 100% | 172 | 398.6 | [179.55, 4173] (lebar 3993.45) | 0.05 | 4167 | 80 | 0.34s | OK |
| 7 | MTU1280_loss5_rtt100 | cand-t2.0-r3 | 100/100 | 100% | 324 | 2327 | [2324.05, 2433.45] (lebar 109.4) | 0.39 | 4399 | 227 | 0.82s | OK |
| 8 | MTU1280_loss1_rtt50 | cand-t2.0-r3 | 40/40 | 100% | 176.5 | 2174.05 | [189, 2182] (lebar 1993) | 0.1 | 4199 | 83 | 0.43s | OK |
| 9 | MTU1280_loss5_rtt100 | cand-t3.0-r4 | 100/100 | 100% | 323 | 3330.75 | [3322, 6321.15] (lebar 2999.15) | 0.25 | 4290 | 216 | 0.87s | OK |
| 10 | MTU1500_loss5_rtt50 | hybrid-default | 40/40 | 100% | 179 | 4187.05 | [4174.1, 15371] (lebar 11196.9) | 0.35 | 4418 | 92 | 0.42s | OK |
| 11 | MTU1280_loss5_rtt100 | hybrid-default | 100/100 | 100% | 323 | 4328 | [4323, 8483.95] (lebar 4160.95) | 0.38 | 4301 | 211 | 0.82s | OK |
| 12 | MTU1400_loss5_rtt100 | cand-t3.0-r3 | 40/40 | 100% | 321 | 3329.15 | [3322.3, 6319] (lebar 2996.7) | 0.28 | 4147 | 0 | 0.33s | OK |
| 13 | MTU1400_loss5_rtt100 | hybrid-default | 40/40 | 100% | 325 | 8483.05 | [4332, 15521] (lebar 11189) | 0.4 | 4270 | 84 | 0.37s | OK |
| 14 | MTU1500_loss5_rtt50 | cand-t2.0-r4 | 40/40 | 100% | 171 | 2283.45 | [2172, 5777] (lebar 3605) | 0.3 | 4128 | 0 | 0.33s | OK |
| 15 | MTU1500_loss5_rtt50 | cand-t3.0-r4 | 40/40 | 100% | 172 | 3173.1 | [3172, 6171] (lebar 2999) | 0.38 | 4197 | 0 | 0.29s | OK |
| 16 | MTU1280_loss5_rtt100 | cand-t2.0-r4 | 100/100 | 100% | 322 | 4322.1 | [2323, 5922] (lebar 3599) | 0.35 | 4347 | 218 | 0.77s | OK |
| 17 | MTU1400_loss5_rtt100 | cand-t2.0-r4 | 40/40 | 100% | 322 | 2323 | [2322, 4323] (lebar 2001) | 0.3 | 4129 | 0 | 0.29s | OK |
| 18 | MTU1280_loss1_rtt50 | cand-t2.0-r4 | 40/40 | 100% | 171 | 2172.05 | [174, 2175] (lebar 2001) | 0.08 | 4195 | 82 | 0.31s | OK |
| 19 | MTU1400_loss5_rtt100 | cand-t3.0-r4 | 40/40 | 100% | 337 | 3491.05 | [3333, 11743] (lebar 8410) | 0.32 | 4128 | 0 | 0.51s | OK |
| 20 | MTU1500_loss5_rtt50 | cand-t3.0-r3 | 40/40 | 100% | 187.5 | 3200 | [3190.2, 3202] (lebar 11.8) | 0.38 | 4181 | 0 | 0.5s | OK |

## 3. Estimasi Durasi Eksperimen Utama (81 Skenario x 100 Run = 8.100 Run)

- **Kisaran Estimasi Total Waktu:** **4.69 jam s.d. 5.7 jam** (feasible diselesaikan dalam jadwal penelitian dengan fitur *resume* -Nama).
- **Kriteria Lolos Tahap 4:**
  1. Fragmentasi IKE teramati secara empiris pada berkas .pcap (Encrypted Fragment RFC 7383): **TERPENUHI** (lihat bukti-fragmentasi.txt).
  2. Parameter teroptimasi dipilih berdasarkan trade-off *success rate*, *handshake time* (median & p95 Bootstrap CI), retransmisi, dan *overhead*: **TERPENUHI (cand-t2.0-r3)**.
  3. Estimasi waktu total *feasible*: **TERPENUHI**.
  4. Skrip otomatisasi & QC lolos uji tanpa intervensi manual: **TERPENUHI**.
