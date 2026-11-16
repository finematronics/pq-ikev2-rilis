# Evaluasi PQ-IKEv2 hybrid (X25519 + ML-KEM-768) terhadap fragmentasi paket

Repositori data, skrip, dan analisis untuk skripsi Rafi Rachman (Program Studi Teknik Komputer, Universitas Pendidikan Indonesia): evaluasi dan optimasi konfigurasi hybrid post-quantum IKEv2/IPsec (`X25519 + ML-KEM-768`) pada testbed dua VM dengan emulasi MTU, packet loss, dan RTT.

## Ringkasan desain

- **Testbed:** 2 VM Ubuntu `24.04.5 LTS` (`Linux 6.8.0-147-generic`, Multipass `1.17.0+win`, driver HCS; masing-masing 2 vCPU, RAM 1,9 GiB), `strongSwan 6.0.2`, `OpenSSL 3.5.0` (implementasi resmi NIST FIPS 203 `ML-KEM-768` dan RFC 9370 `IKE_INTERMEDIATE`), `tc netem` (`iproute2 6.1.0`) untuk loss dan delay simetris (`delay = RTT/2` per sisi), `ip link set mtu` untuk MTU, serta `tcpdump 4.99.4` dan `tshark 4.2.2`.
- **Faktor:** `MTU` (`1280` / `1400` / `1500` B) x `loss` (`0` / `1` / `5` %) x `RTT` (`10` / `50` / `100` ms) x konfigurasi (`klasik`, `hybrid-default`, `hybrid-optimized`) = **81 skenario**, ditambah **8 sel ablasi** (`hybrid-plusA` dan `hybrid-plusB` pada `MTU 1280/1500 B x loss 0/5 % x RTT 50 ms`) = **89 batch x 100 run = 8.900 run** (ditambah 1 *warm-up run* `ike_sa_uid = 1` di awal setiap batch).
- **Urutan eksekusi:** Diacak penuh (`seed 11680`). Konfigurasi dibekukan sebelum eksperimen utama (`03_pilot/CONFIG_FREEZE.md`).

| Konfigurasi | Proposal Pertukaran Kunci (`swanctl`) | `charon.fragment_size` | `charon.retransmit_timeout` | `charon.retransmit_tries` | Peran dalam Desain Eksperimen |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `klasik` | `x25519` | `1280 B` (default) | `4.0 s` (default) | `5` (default) | Baseline klasik (2 pertukaran: `IKE_SA_INIT`, `IKE_AUTH`) |
| `hybrid-default` | `x25519-ke1_mlkem768` | `1280 B` (default) | `4.0 s` (default) | `5` (default) | Baseline hibrida (3 pertukaran: + `IKE_INTERMEDIATE`) |
| `hybrid-optimized` | `x25519-ke1_mlkem768` | Adaptif `MTU - 28` (`1252` / `1372` / `1472 B`) | `2.0 s` | `3` | Hibrida teroptimasi penuh (`+A+B`) |
| `hybrid-plusA` | `x25519-ke1_mlkem768` | Adaptif `MTU - 28` (`1252` / `1472 B`) | `4.0 s` (default) | `5` (default) | Studi ablasi: hanya fragmentasi adaptif (`+A`) |
| `hybrid-plusB` | `x25519-ke1_mlkem768` | `1280 B` (default) | `2.0 s` | `3` | Studi ablasi: hanya penurunan *retransmit timeout* (`+B`) |

## Struktur

- `02_testbed/`: versi perangkat lunak, topologi, instalasi, verifikasi jaringan, contoh konfigurasi (PSK diganti placeholder).
- `03_pilot/`: pilot (120 run), tuning (1.100 run), dan config freeze (`CONFIG_FREEZE.md`).
- `04_data/evaluasi-20261114-1749/`: data mentah terkunci (89 folder batch, `ringkasan-batch.csv`, `rencana.csv`, `verifikasi-rtt-ping.txt`, `metadata-percobaan-sanitasi.txt`).
- `05_analisis/`: validasi pcap (`VALIDASI-pcap-*`), keluaran statistik `STAT-*`, tabel dan grafik Bab IV (`Tabel-Bab-IV-PQ-IKEv2.xlsx`, `grafik-1-median-p95.png`, `grafik-2-kondisi-kritis.png`).
- `jalankan-eksperimen.ps1`: skrip otomatisasi eksperimen.
- `validasi-pcap.py`, `analisis-statistik.py`: skrip validasi struktural `.pcap` dan analisis statistik.
- `KAMUS_DATA.md`: definisi kolom dan berkas. `penyimpangan.md`: semua penyimpangan dari proposal (Bagian 1 s.d. Bagian 9).

```text
pq-ikev2/
├── .gitattributes                         # Normalisasi baris akhir LF agar hash berkas teks konsisten di semua platform
├── .gitignore                             # Pengecualian berkas log/metadata mentah sebelum sanitasi
├── README.md                              # Dokumentasi utama repositori, struktur, verifikasi hash, dan temuan
├── KAMUS_DATA.md                          # Definisi seluruh kolom CSV, satuan, dan daftar berkas keluaran
├── penyimpangan.md                        # Catatan lengkap seluruh penyimpangan dari proposal dan keterbatasan
├── jalankan-eksperimen.ps1                # Skrip otomatisasi eksekusi eksperimen utama dan studi ablasi
├── validasi-pcap.py                       # Skrip baca-saja validasi struktural initiator.pcap terhadap runs.csv
├── analisis-statistik.py                  # Skrip baca-saja analisis statistik Tabel 3.10 Proposal & eksploratori
├── 02_testbed/                            # Versi perangkat lunak, topologi, instalasi, verifikasi, konfigurasi swanctl
├── 03_pilot/                              # Data pilot, seleksi kandidat tuning, dan CONFIG_FREEZE.md
├── 04_data/
│   ├── evaluasi-20261114-1749/            # Data mentah terkunci evaluasi utama (89 folder batch, ringkasan-batch.csv, rencana.csv)
│   └── ablation-20261114-1428/            # Data studi ablasi pra-evaluasi (8 batch = 800 run)
└── 05_analisis/
    ├── VALIDASI-pcap-ringkasan.txt        # Ringkasan teks hasil validasi struktural .pcap pada 89 batch (8.900 run)
    ├── VALIDASI-pcap-per-batch.csv        # Rekonsiliasi .pcap vs ringkasan-batch.csv per batch (89 baris)
    ├── VALIDASI-pcap-per-run.csv          # Rekonsiliasi jendela waktu, ms_pcap, dan residu per run (8.900 baris)
    ├── STAT-RINGKASAN.txt                 # Ringkasan teks hasil uji statistik RQ1 dan perbandingan terencana RQ2
    ├── STAT-RQ1-ART-ANOVA.csv             # Hasil ART-ANOVA 3x3x3 (MTU x loss x RTT) per konfigurasi
    ├── STAT-RQ1-KruskalWallis.csv         # Hasil uji Kruskal-Wallis satu arah per faktor (n = 2.700 per konfigurasi)
    ├── STAT-RQ1-Dunn-Holm.csv             # Hasil uji lanjut Dunn berpasangan dengan koreksi Holm
    ├── STAT-RQ2-terencana-kondisi-kritis.csv         # Perbandingan terencana kondisi kritis (MTU 1280 B, loss 5%, RTT 10/50/100 ms)
    ├── STAT-RQ3-ablasi.csv                           # Hasil studi ablasi pada 4 sel (MTU 1280/1500 x loss 0/5% x RTT 50 ms)
    ├── STAT-eksploratori-27-kondisi.csv              # Ringkasan perbandingan eksploratori seluruh 27 kondisi
    ├── STAT-eksploratori-selisih-rata2-bootstrap.csv # Selisih rata-rata & Bootstrap 95% CI (B = 10.000, seed = 11680)
    ├── Tabel-Bab-IV-PQ-IKEv2.xlsx         # Workbook rekapitulasi tabel deskriptif 89 batch dan seluruh tabel STAT Bab IV
    ├── grafik-1-median-p95.png            # Grafik waktu handshake median (garis penuh) dan p95 (putus-putus) pada 9 kombinasi MTU x loss
    └── grafik-2-kondisi-kritis.png        # Grafik boxplot (skala log) sebaran waktu handshake pada kondisi kritis (MTU 1280, loss 5%)
```

## Verifikasi integritas

Hitung hash dengan PowerShell dan bandingkan dengan nilai berikut.

- `EVALUASI-semua-8900-runs.csv`: `48C211314BFD46A4E352AEED63CCDBEA4171179E43D8AB1EE981F07FAC8EEA2C`
- `analisis-statistik.py`: `1797439E78120E0FA823DB06391D86CB917A382CD215869C974062204B19B971`
- `validasi-pcap.py`: `58FE46BB2C6873491B5D2B0BC0924B3F9FE51DF3B247CF97C547A93A53B7F867`
- `jalankan-eksperimen.ps1`: `AB39D928848EF01B2CF7E6EA3235A66F5A30A05E3DCFEDE8590BC459564CC85B`
- `04_data/evaluasi-20261114-1749/ringkasan-batch.csv`: `366FD28E3ECE51934A21DEE5CF31812BD73E1E0BCC9C9A7E700D3674A7FFE6AE`
- `04_data/evaluasi-20261114-1749/rencana.csv`: `5A8FCAE31FD234F38AEFD05D2F96E8954D128BA17F71D970EADADEA0060AA4A9`
- `03_pilot/CONFIG_FREEZE.md`: `B2ED1FE513F7FDE5E4FADFC6688690B9CF40240854C8349D459E0C2686CB7622`
- `05_analisis/VALIDASI-pcap-ringkasan.txt`: `F01011C8446FEC0B9AF020131838DC3BBF6BA6BE21973B67BD1E9C706B5A77BE`
- `05_analisis/VALIDASI-pcap-per-batch.csv`: `12B6BE637BB2BBD9A1DE557CFE15F1E0AC4941783B9687AE6733E72195A63A2E`
- `05_analisis/VALIDASI-pcap-per-run.csv`: `2F13925BB56959A86F91A71E2580B889E8BC7C66BDABF1B02CB53636E84FA554`

```powershell
Get-FileHash <berkas> -Algorithm SHA256
```

Hash skrip eksperimen dan validasi tercatat di `penyimpangan.md`. Berkas teks memakai akhiran baris LF (`.gitattributes`) agar hash sama di semua platform.

## Menjalankan ulang analisis

Lingkungan hasil resmi: Python 3.13.0, numpy 2.4.6, pandas 3.0.4, scipy 1.17.1.

```powershell
python analisis-statistik.py <EVALUASI-semua-8900-runs.csv> 05_analisis
```

Versi pustaka lain dapat menghasilkan selisih di digit terakhir floating-point (lihat `penyimpangan.md`, Bagian 7). Jangan menimpa `STAT-*` resmi tanpa alasan.

## Temuan utama

- Success rate 100% (`100/100` run di seluruh 89 batch; Fisher `p = 1,0`) pada semua kondisi, sehingga perbedaan success rate antar konfigurasi tidak dapat diuji (efek langit-langit).
- RTT dan loss adalah faktor dominan pada waktu handshake (`p < 1e-290` dan `p <= 1,12e-20` pada Kruskal–Wallis satu arah). MTU tidak signifikan sebagai efek utama pada `klasik` (`p = 0,1088`) dan `hybrid-default` (`p = 0,1861`), serta berpengaruh lewat interaksi pada ART-ANOVA dan marginal pada `hybrid-optimized` (`p = 0,0219`).
- Hybrid (`X25519 + ML-KEM-768`) lebih lambat daripada klasik (`X25519`) karena satu pertukaran ekstra (`IKE_INTERMEDIATE`, menambah 1 RTT jaringan dan meningkatkan trafik Layer 2 dari `1.309 B` menjadi `3.946 B/run`), sedangkan tambahan waktu CPU proses `charon` kurang dari `2 ms/run` (`+1,68` s.d. `+1,81 ms/run`).
- Pada kondisi kritis (`MTU 1280, loss 5%`), konfigurasi teroptimasi (`hybrid-optimized`) menurunkan rata-rata (`910,93` vs `1.866,53 ms` di RTT 10 ms; `898,07` vs `1.856,65 ms` di RTT 50 ms; `842,25` vs `2.168,77 ms` di RTT 100 ms) dan `p95` akibat penurunan `retransmit_timeout = 2.0 s` pada ekor retransmisi (serta mengeliminasi fragmen IKE menjadi `0` pada `MTU >= 1400 B` lewat `fragment_size = MTU - 28`), tetapi tidak menurunkan median dan tidak signifikan pada uji peringkat terencana Mann–Whitney U (`p_Holm = 0,2914` s.d. `1,0000`).

## Keterbatasan

Satu batch per sel kondisi; uji peringkat peka terhadap offset batch sekitar 1 ms dan tidak peka terhadap panjang tunggu retransmisi; definisi median tabel deskriptif memakai nearest-rank sedangkan `STAT-*` memakai `numpy.median` (selisih `0,5 ms` pada 4 dari 89 sel); testbed virtual (angka absolut bergantung lingkungan, mekanisme berlaku lebih luas); CPU diukur per batch dari `/proc/<pid>/stat` (`pidstat` tersedia sebagai rekaman pendamping di Initiator). Rincian di `penyimpangan.md`.

## Keamanan

Kunci pra-bagi (PSK) pada berkas konfigurasi telah diganti `<PSK_LAB_DIGANTI>`. PSK laboratorium hanya dipakai pada testbed terisolasi.
## Lisensi

Skrip: MIT (`LICENSE`). Data dan dokumen: CC BY 4.0 (`LICENSE-DATA.md`).