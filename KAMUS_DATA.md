# KAMUS DATA (DATA DICTIONARY) EKSPERIMEN PQ-IKEv2

Dokumen ini mendefinisikan setiap kolom pada `ringkasan-batch.csv`, `runs.csv`, dan `rencana.csv` beserta sumber pengukurannya agar tidak terjadi pencampuran sumber data pada Bab IV.

## 1. Aturan Sumber Data Utama Bab IV & Validasi Silang `.pcap`
1. **Waktu Handshake & Jumlah Retransmisi Utama (`runs.csv`):**
   - Karena titik tangkap `tcpdump` (`initiator.pcap`) berada setelah antrean `tc qdisc netem` pada sisi *egress* Initiator, request Initiator yang jatuh di *egress* tidak terekam di `.pcap`. Oleh karena itu, sumber utama waktu handshake adalah **`ms_total_swanctl`** dan sumber utama jumlah retransmisi per run adalah **`retransmisi`** (serta agregatnya `rata2_ms`, `median_ms`, `p95_ms`, `persen_retrans`, `rata_retransmisi` di `ringkasan-batch.csv`).
   - Ekstraksi `.pcap` (menggunakan jendela waktu `[mulai_epoch_ns, selesai_epoch_ns]` dan berakhir pada `IKE_AUTH Responder Response`, `MID 0–2`) digunakan sebagai **validator struktural**:
     * **Validasi Waktu:** `residu = ms_total_swanctl − (ms_pcap + RTT/2)` bernilai sekitar **`11–13 ms`** (seluruh waktu pemrosesan di luar jendela `.pcap`, termasuk persiapan sebelum paket pertama keluar dan pemrosesan setelah paket terakhir diterima) pada run normal, atau bergeser sebesar kelipatan `retransmit_timeout` jika `IKE_SA_INIT Request` pertama jatuh di *egress* Initiator.
     * **Validasi Retransmisi:** Menggunakan aturan **`MID 0–2` (tanpa paket teardown `INFORMATIONAL MID=03`), terdapat duplikat request atau jeda antar-paket `>= 0,8 x retransmit_timeout_s`**, dengan selisih terhadap kolom `retransmisi` hanya terjadi apabila paket pertama `IKE_SA_INIT` jatuh di *egress* Initiator.
2. **Perhitungan Fragmen & Overhead Byte Tertangkap (`ringkasan-batch.csv`):**
   - Wajib menggunakan kolom **`frag_ike_total`** dan **`rata_bytes`** dari `ringkasan-batch.csv`. Karena paket yang dijatuhkan oleh `tc netem` tidak masuk ke berkas `.pcap`, kedua metrik ini merepresentasikan **"byte/fragmen tertangkap setelah loss emulasi"** (bukan total byte/fragmen yang dikirim sebelum loss).
   - `frag_ike_total`: Menghitung jumlah baris keluaran `tshark` yang memuat teks `"(fragment"` (*Encrypted Fragment*, RFC 7383) dari seluruh berkas `.pcap` pada batch tersebut (termasuk fragmen kirim ulang yang lolos dari `netem`).
   - `rata_bytes`: Menghitung rata-rata total byte bingkai Ethernet (Layer 2) per run yang tertangkap di `initiator.pcap` untuk paket IKEv2 di luar *teardown* (`isakmp && isakmp.exchangetype != 37`).
3. **Kolom Log yang Tidak Dipakai (`frag_ike_log`) & Perbedaan `bytes_ike_log` vs `rata_bytes`:**
   - `frag_ike_log` (`runs.csv`): Bernilai `0` di seluruh 8.900 baris karena ketidakcocokan regex terhadap format log `charon` di `strongSwan 6.0.2`. Kolom ini **diabaikan/tidak digunakan**.
   - `bytes_ike_log` (`runs.csv`): Ukuran payload IKEv2 (Layer 7) yang dilaporkan log `charon` saat dikirim daemon (`1.133 B` pada `klasik`, `3.567 B` pada `hybrid` tanpa fragmen, `3.632 B` pada `hybrid` dengan 2 fragmen pada kondisi `loss 0%`).
   - `rata_bytes` (`ringkasan-batch.csv`): Ukuran total bingkai Ethernet (Layer 2) yang tertangkap di `.pcap` tanpa paket teardown `INFORMATIONAL` (`1.309 B` pada `klasik`, `3.835 B` pada `hybrid` tanpa fragmen, `3.946 B` pada `hybrid` dengan 2 fragmen pada kondisi `loss 0%`). Selisih keduanya pada `loss 0%` adalah header `Ethernet (14B) + IPv4 (20B) + UDP (8B) = 42B` per paket di port 500 dan `46B` (termasuk 4B Non-ESP Marker) per paket di port 4500.
4. **89 Warm-up Run:** Setiap batch menjalankan 1 *warm-up run* (`ike_sa_uid = 1`) sebelum `tcpdump` dimulai. Run pemanasan ini sengaja tidak masuk ke dalam `runs.csv` maupun `.pcap`, sehingga `percobaan = 1` pada `runs.csv` selalu dimulai dari `ike_sa_uid = 2`.

## 2. Definisi Kolom `ringkasan-batch.csv`
- `idx`: Nomor urut eksekusi batch (1 s.d. 89) sesuai pengacakan `rencana.csv` (`seed = 11680`).
- `kondisi`: Kombinasi faktor jaringan `MTU{1280,1400,1500}_loss{0,1,5}_rtt{10,50,100}`.
- `konfigurasi`: Varian yang diuji (`klasik`, `hybrid-default`, `hybrid-optimized`, `hybrid-plusA`, `hybrid-plusB`).
- `valid`, `ok`, `gagal`, `invalid`: Jumlah run valid (`100/100`), berhasil (`100`), gagal (`0`), dan tidak valid (`0`).
- `success_rate_persen`: Persentase keberhasilan pembentukan SA (`100%` di seluruh 89 batch).
- `rata2_ms`: Nilai rata-rata aritmetika (`mean`) waktu pembentukan tunnel per batch (`ms`) dari `ms_total_swanctl`.
- `persen_retrans`: Persentase run dalam batch yang mengalami minimal 1 kali retransmisi handshake (`retransmisi > 0`).
- `persen_lewat_1s`: Persentase run dalam batch yang membutuhkan waktu `>= 1.000 ms`.
- `median_ms`, `p95_ms`: Persentil ke-50 dan ke-95 yang dihitung di dalam fungsi `Hitung-StatistikWaktu` menggunakan metode **Nearest-Rank** (`idx = ceil(p * n) - 1`).
- `p95_ci_bawah`, `p95_ci_atas`, `p95_ci_lebar`: Batas bawah, batas atas, dan lebar interval kepercayaan Bootstrap 95% yang dihitung oleh fungsi `Hitung-StatistikWaktu` (`B = 1.000` resamples, metode Nearest-Rank, dengan seed tetap yang tertanam di skrip (hash AB39D928848EF01B2CF7E6EA3235A66F5A30A05E3DCFEDE8590BC459564CC85B)).
- `rata_retransmisi`: Rata-rata jumlah kejadian kirim ulang (retransmisi) handshake per run dalam satu batch.
- `rata_bytes`: Rata-rata total byte frame Ethernet paket handshake IKEv2 per run yang tertangkap pada `initiator.pcap` setelah loss emulasi (filter `isakmp && isakmp.exchangetype != 37`).
- `frag_ike_total`: Total baris paket fragmen terenkripsi IKEv2 (`"(fragment"`, RFC 7383) yang tertangkap pada `initiator.pcap` setelah loss emulasi dalam satu batch.
- `frag_ip_total`: Total paket tertangkap yang mengalami fragmentasi di lapisan IP (`ip.flags.mf == 1 || ip.frag_offset > 0`) dari `.pcap`.
- `cpu_init_s`, `cpu_resp_s`: Total waktu CPU (`utime + stime` dari `/proc/<pid>/stat`) daemon `charon` selama 100 run di VM Initiator dan Responder (detik).
- `detik_per_run`, `detik_overhead`, `qc`: Durasi eksekusi per run, waktu persiapan per batch, dan status pemeriksaan kualitas (`OK`).
## Berkas analisis statistik (05_analisis/STAT-*)

Dihasilkan oleh `analisis-statistik.py` dari `EVALUASI-semua-8900-runs.csv`. Satuan waktu: ms (nilai `rata2_*` dan `median_*`), p-value tanpa satuan.

- `STAT-RQ1-ART-ANOVA.csv`: ART-ANOVA 3x3x3 per konfigurasi (klasik, hybrid-default, hybrid-optimized). Kolom: konfigurasi, efek, df, df_galat, F, p.
- `STAT-RQ1-KruskalWallis.csv` dan `STAT-RQ1-Dunn-Holm.csv`: Kruskal-Wallis dan uji lanjut Dunn dengan koreksi Holm.
- `STAT-RQ2-terencana-kondisi-kritis.csv`: perbandingan terencana pada kondisi kritis (MTU 1280, loss 5%, RTT 10/50/100). Kolom: keluarga, A, B, MTU, loss, RTT, nA, nB, arah, rata2_A, rata2_B, median_A, median_B, retx_A_persen, retx_B_persen, MWU_p, cliff_delta_A_vs_B, sukses_A, sukses_B, Fisher_p, cohen_h, MWU_p_Holm. H1 memakai uji satu arah (less), H0(3) dua arah.
- `STAT-RQ3-ablasi.csv`: ablasi pada 4 sel (MTU 1280/1500 x loss 0/5 x RTT 50). Kolom: MTU, loss, RTT, A, B, nA, nB, selisih_rata2_ms, ci95_bawah, ci95_atas (bootstrap B=10000, seed 11680), MWU_p_2arah, cliff_delta.
- `STAT-eksploratori-27-kondisi.csv` dan `STAT-eksploratori-selisih-rata2-bootstrap.csv`: ringkasan eksploratori seluruh 27 kondisi.
- `STAT-RINGKASAN.txt`: ringkasan teks.
- Lingkungan: Python 3.13.0, numpy 2.4.6, pandas 3.0.4, scipy 1.17.1. Skrip SHA-256 `1797439E78120E0FA823DB06391D86CB917A382CD215869C974062204B19B971`.