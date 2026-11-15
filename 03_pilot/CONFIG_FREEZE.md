# CONFIG FREEZE — Parameter Teroptimasi PQ-IKEv2 (Tahap 4)

- **Peneliti:** Rafi Rachman
- **Tanggal Penetapan (Freeze):** 2026-11-14
- **Sumber Data Pilot & Tuning:**
  - Uji Instrumen & Baseline Klasik (6 skenario x 20 run = 120 run): `03_pilot/uji-20261114-1219`
  - Seleksi Kandidat Tuning (20 skenario = 1.100 run): `03_pilot/tuning-20261114-1258`
  - Studi Ablasi Pra-Evaluasi / Verifikasi Silang (8 skenario x 100 run = 800 run): `04_data/ablation-20261114-1428` *(data verifikasi silang; sel ablasi utama diintegrasikan ke dalam 89 skenario `-Set evaluasi`)*
- **Skrip Otomatisasi Resmi untuk Evaluasi Utama:** `jalankan-eksperimen.ps1` (`SHA-256: AB39D928848EF01B2CF7E6EA3235A66F5A30A05E3DCFEDE8590BC459564CC85B`)
- **Seed Pengacakan Evaluasi Utama (`-Set evaluasi`):** `11680` (89 skenario = 81 skenario evaluasi utama + 8 skenario ablasi)
- **Mekanisme Penerapan:** `/etc/strongswan.d/zz-eksperimen.conf` (blok `charon { ... }`) di kedua VM, diikuti `systemctl restart strongswan` dan `swanctl --load-all`.
- **Status Konfigurasi:** **TERKUNCI (FROZEN)** — Parameter di bawah ini digunakan secara tetap untuk seluruh skenario evaluasi utama (Tahap 5).

---

## 1. Tabel Parameter Terkunci (Sesuai Tabel 3.8 Proposal & Hasil Tuning)

| Parameter (`strongSwan/charon`) | Klasik (Baseline) | Hybrid Default | Hybrid Teroptimasi (FROZEN) | Hybrid +A (Ablation) | Hybrid +B (Ablation) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Proposal Key Exchange** | `x25519` | `x25519-ke1_mlkem768` | `x25519-ke1_mlkem768` | `x25519-ke1_mlkem768` | `x25519-ke1_mlkem768` |
| **`charon.fragment_size`** | `1280` (default) | `1280` (default) | **Adaptif `MTU - 28` (`1252` / `1372` / `1472`)** | `MTU - 28` | `1280` |
| **`charon.retransmit_timeout`** | `4.0` s (default) | `4.0` s (default) | **`2.0` s** *(hasil tuning; lihat `penyimpangan.md`)* | `4.0` s | `2.0` s |
| **`charon.retransmit_tries`** | `5` (default) | `5` (default) | **`3`** *(mengikuti Tabel 3.8 Proposal)* | `5` | `3` |
| **Metode Autentikasi** | PSK | PSK | PSK | PSK | PSK |

---

## 2. Justifikasi Pemilihan Parameter (`cand-t2.0-r3`) & Catatan Keterbatasan Metodologis

1. **Peran `fragment_size = MTU - 28` (Eliminasi Fragmentasi IKE pada MTU >= 1400 vs Efek Waktu):**
   - Pesan `IKE_INTERMEDIATE` yang membawa kunci publik `ML-KEM-768` berukuran `1.249 byte` pada level IP/UDP.
   - Pada konfigurasi `hybrid-default` (`fragment_size = 1280`), pesan tersebut selalu terpecah menjadi 2 fragmen IKE (`1294 B` dan `112 B` pada frame Ethernet) di seluruh nilai MTU (`1280`, `1400`, maupun `1500`).
   - Dengan `fragment_size = MTU - 28` (`1372 B` pada MTU 1400 dan `1472 B` pada MTU 1500), **terbukti secara empiris bahwa jumlah paket fragmen IKE turun menjadi `0` paket** pada MTU 1400 dan MTU 1500 (menghemat 1 paket per handshake dari 7 menjadi 6 paket dan menghemat `111 byte/run` pada kondisi tanpa loss).
   - *Catatan Batas Klaim Empiris:* Meskipun secara teoretis pengurangan jumlah paket dari 7 ke 6 menurunkan peluang terjadinya minimal 1 retransmisi pada `loss 5%` dari `1 - (0,95)^7 = 30,17%` menjadi `1 - (0,95)^6 = 26,49%` (mekanisme teoretis *fragment loss amplification*), pembanding pada data evaluasi `hybrid-optimized` di kondisi `loss 5%` adalah `300` run berfragmen (`MTU 1280`: laju retransmisi `28,67%`) melawan `600` run tanpa fragmen (`MTU 1400` dan `MTU 1500`: laju retransmisi `28,17%`). Galat baku (`SE`) selisih dua proporsi tersebut adalah `3,20` poin persentase (sekitar `3,2` poin), sedangkan efek teoretis `3,68` poin persentase ≈ `1,15 SE` (`z ≈ 1,15`), sehingga tidak terdeteksi secara statistik (demikian pula `5,67%` vs `6,00%` pada `loss 1%`). Hasil studi ablasi membuktikan bahwa `fragment_size = MTU - 28` saja (`+A`) tidak terbukti mengurangi waktu handshake (`+308 ms [-622, +1.342]` di MTU 1280 dan `-115 ms [-956, +803]` di MTU 1500 terhadap `hybrid-default` pada `loss 5%, RTT 50 ms`).

2. **Peran Dominan `retransmit_timeout = 2.0 s` (Penurunan Deterministik Undakan Waktu Retransmisi):**
   - Di bawah *packet loss*, distribusi waktu handshake IKEv2 bersifat **diskrit berundak (*multimodal step distribution*)** mengikuti rumus `T = T_dasar + sum(timeout * 1,8^i)`.
   - Pemilihan `retransmit_timeout = 2.0 s` secara mekanis memangkas penalti waktu tunggu pada setiap undakan retransmisi sebesar **33,3% dibanding `3.0 s`** dan **50,0% dibanding `4.0 s` (default)**. Studi ablasi pada `loss 5%, RTT 50 ms` mengonfirmasi bahwa `retransmit_timeout = 2.0 s` (`+B`) merupakan faktor dominan yang menurunkan rata-rata waktu handshake secara bermakna (`-979 ms [-1.620, -348]` pada MTU 1280 dan `-862 ms [-1.480, -282]` pada MTU 1500 terhadap `hybrid-default`; 95% CI tidak melewati nol).

3. **Keterbatasan Pembuktian Empiris `retransmit_tries = 3` vs `4` & Peran *Success Rate*:**
   - Dengan `tries = 3` pada `loss = 5%` per arah, peluang gagal teoretis per handshake penuh hanya sekitar `0,03%–0,06%`.
   - Karena seluruh run pada fase tuning dan evaluasi utama berhasil 100% sebelum mencapai percobaan ke-4, **efek perbedaan antara `retransmit_tries = 3` dan `4` tidak dapat dibuktikan dari data**. Pemilihan `retransmit_tries = 3` mengikuti Tabel 3.8 Proposal, dan *Success Rate* (`100%`) dilaporkan sebagai temuan keandalan umum, bukan pembeda antar-konfigurasi.

4. **Ketidakstabilan `p95` pada `Loss 5%`, Metode *Nearest-Rank*, & Konsultasi Pembimbing:**
   - Pada `loss 5%`, peluang kumulatif `<= 1` retransmisi berada dekat dengan persentil ke-95, sehingga nilai `p95` dan Bootstrap 95% CI (`Hitung-StatistikWaktu`, `B = 1.000` resamples) melompat di antara Undakan 1 dan Undakan 2.
   - Keputusan mempertahankan `n = 100` ulangan per skenario beserta pelaporan ketidakstabilan `p95` pada sel `loss 5%` ini **telah dikonsultasikan dan disetujui secara lisan oleh dosen pembimbing pada 14-15 November 2026**, tanpa dokumentasi chat/email tertulis (akan dicatatkan pada lembar bimbingan resmi saat penyerahan draf Bab IV). Analisis dilengkapi dengan metrik pendamping: **rata-rata (`rata2_ms`)**, **persentase run yang mengalami retransmisi (`persen_retrans`)**, dan **persentase run yang melewati ambang 1 detik (`persen_lewat_1s`)**.

---

## 3. Hasil Pengujian Uji Instrumen (`-Set uji`, Dihitung Ulang dengan *Nearest-Rank* dari `runs.csv`)

*Catatan Kronologis:* Data 6 batch `uji` dan 20 batch `tuning` di bawah ini dieksekusi sebelum penambahan fitur 1 *warm-up run* di skrip, kemudian nilai `median_ms`, `p95_ms`, `Bootstrap 95% CI` (`B = 1.000`), `rata2_ms`, dan `persen_retrans` dihitung ulang dari berkas mentah `runs.csv` menggunakan metode **Nearest-Rank**.

| Idx | Kondisi (`MTU_Loss_RTT`) | Konfigurasi | Valid | SR | Mean (`ms`) | Median (`ms`) | `p95` Nearest-Rank (`ms`) | Bootstrap 95% CI `p95` (`ms`) | `% Run Retrans` | Rata Bytes | Frag IKE | QC |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `MTU1280_loss5_rtt100` | `hybrid-default` | 20/20 | 100% | 2326.7 | 338 | 4332 | [4325, 4340] | 50% | 4268 | 42 | OK |
| 2 | `MTU1500_loss0_rtt10` | `hybrid-default` | 20/20 | 100% | 52.15 | 51 | 61 | [54, 62] | 0% | 4160 | 40 | OK |
| 3 | `MTU1280_loss5_rtt100` | `hybrid-optimized` | 20/20 | 100% | 777.3 | 324 | 3333 | [337, 3344] | 15% | 4224 | 41 | OK |
| 4 | `MTU1280_loss5_rtt100` | `klasik` | 20/20 | 100% | 823.65 | 223 | 4218 | [234, 4239] | 15% | 1574 | 0 | OK |
| 5 | `MTU1500_loss0_rtt10` | `klasik` | 20/20 | 100% | 50.15 | 45 | 76 | [55, 95] | 0% | 1523 | 0 | OK |
| 6 | `MTU1500_loss0_rtt10` | `hybrid-optimized` | 20/20 | 100% | 59.6 | 55 | 77 | [65, 105] | 0% | 4049 | 0 | OK |

---

## 4. Hasil Pengujian 20 Skenario Tuning (`-Set tuning`, Dihitung Ulang dengan *Nearest-Rank* dari `runs.csv`)

| Idx | Kondisi (`MTU_Loss_RTT`) | Konfigurasi | Valid | SR | Mean (`ms`) | Median (`ms`) | `p95` Nearest-Rank (`ms`) | Bootstrap 95% CI `p95` (`ms`) | `% Run Retrans` | Rata Bytes | Frag IKE | QC |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `MTU1280_loss1_rtt50` | `cand-t3.0-r4` | 40/40 | 100% | 172.15 | 172 | 176 | [174, 183] (lebar 9) | 0% | 4160 | 80 | OK |
| 2 | `MTU1500_loss5_rtt50` | `cand-t2.0-r3` | 40/40 | 100% | 624.35 | 175 | 2176 | [2171, 2182] (lebar 11) | 22.5% | 4069 | 0 | OK |
| 3 | `MTU1280_loss1_rtt50` | `cand-t3.0-r3` | 40/40 | 100% | 397.35 | 172 | 3169 | [175, 3176] (lebar 3001) | 7.5% | 4227 | 83 | OK |
| 4 | `MTU1280_loss5_rtt100` | `cand-t3.0-r3` | 100/100 | 100% | 1390.7 | 322 | 6321 | [3323, 6325] (lebar 3002) | 28% | 4332 | 217 | OK |
| 5 | `MTU1400_loss5_rtt100` | `cand-t2.0-r3` | 40/40 | 100% | 953.42 | 321 | 2332 | [2323, 7923] (lebar 5600) | 20% | 4140 | 0 | OK |
| 6 | `MTU1280_loss1_rtt50` | `hybrid-default` | 40/40 | 100% | 374.1 | 172 | 200 | [179, 4173] (lebar 3994) | 5% | 4167 | 80 | OK |
| 7 | `MTU1280_loss5_rtt100` | `cand-t2.0-r3` | 100/100 | 100% | 1118.87 | 324 | 2327 | [2324, 2334] (lebar 10) | 37% | 4399 | 227 | OK |
| 8 | `MTU1280_loss1_rtt50` | `cand-t2.0-r3` | 40/40 | 100% | 376.7 | 176 | 2174 | [188, 2182] (lebar 1994) | 10% | 4199 | 83 | OK |
| 9 | `MTU1280_loss5_rtt100` | `cand-t3.0-r4` | 100/100 | 100% | 1098.15 | 323 | 3329 | [3322, 6321] (lebar 2999) | 21% | 4290 | 216 | OK |
| 10 | `MTU1500_loss5_rtt50` | `hybrid-default` | 40/40 | 100% | 1657.6 | 179 | 4187 | [4174, 15371] (lebar 11197) | 30% | 4418 | 92 | OK |
| 11 | `MTU1280_loss5_rtt100` | `hybrid-default` | 100/100 | 100% | 1906.38 | 323 | 4328 | [4323, 8324] (lebar 4001) | 35% | 4301 | 211 | OK |
| 12 | `MTU1400_loss5_rtt100` | `cand-t3.0-r3` | 40/40 | 100% | 1147.32 | 321 | 3329 | [3322, 6319] (lebar 2997) | 25% | 4147 | 0 | OK |
| 13 | `MTU1400_loss5_rtt100` | `hybrid-default` | 40/40 | 100% | 2085.43 | 325 | 8323 | [4329, 15521] (lebar 11192) | 27.5% | 4270 | 84 | OK |
| 14 | `MTU1500_loss5_rtt50` | `cand-t2.0-r4` | 40/40 | 100% | 812.58 | 171 | 2184 | [2172, 5777] (lebar 3605) | 25% | 4128 | 0 | OK |
| 15 | `MTU1500_loss5_rtt50` | `cand-t3.0-r4` | 40/40 | 100% | 1296.2 | 172 | 3173 | [3172, 6171] (lebar 2999) | 35% | 4197 | 0 | OK |
| 16 | `MTU1280_loss5_rtt100` | `cand-t2.0-r4` | 100/100 | 100% | 1085.6 | 322 | 4322 | [2323, 5922] (lebar 3599) | 28% | 4347 | 218 | OK |
| 17 | `MTU1400_loss5_rtt100` | `cand-t2.0-r4` | 40/40 | 100% | 921.42 | 322 | 2323 | [2322, 4323] (lebar 2001) | 27.5% | 4129 | 0 | OK |
| 18 | `MTU1280_loss1_rtt50` | `cand-t2.0-r4` | 40/40 | 100% | 321.88 | 171 | 2172 | [174, 2175] (lebar 2001) | 7.5% | 4195 | 82 | OK |
| 19 | `MTU1400_loss5_rtt100` | `cand-t3.0-r4` | 40/40 | 100% | 1369.25 | 337 | 3342 | [3333, 11743] (lebar 8410) | 25% | 4128 | 0 | OK |
| 20 | `MTU1500_loss5_rtt50` | `cand-t3.0-r3` | 40/40 | 100% | 1308.8 | 183 | 3200 | [3190, 3202] (lebar 12) | 37.5% | 4181 | 0 | OK |

---

## 5. Status Pelaksanaan Eksperimen Utama (`-Set evaluasi`, 89 Skenario, `seed = 11680`)

1. **Verifikasi Skrip Evaluasi Utama:** Skrip `jalankan-eksperimen.ps1` (`SHA-256: AB39D928848EF01B2CF7E6EA3235A66F5A30A05E3DCFEDE8590BC459564CC85B`) menerapkan fungsi `Hitung-StatistikWaktu` dengan metode kuantil **Nearest-Rank** dan Bootstrap 95% CI (`B = 1.000` resamples), **1 *warm-up run*** per batch setelah `tc netem` aktif, filter paket *teardown* `INFORMATIONAL` (`isakmp.exchangetype != 37`), serta metrik pendamping (`rata2_ms`, `persen_retrans`, `persen_lewat_1s`).
2. **Integrasi 89 Skenario Acak (`seed = 11680`):** Eksekusi `-Set evaluasi` menggabungkan 81 skenario evaluasi utama + 8 skenario ablasi = **89 skenario acak** (8.900 run valid + 89 *warm-up run*) dengan **`seed = 11680`**.