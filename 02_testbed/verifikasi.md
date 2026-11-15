# Verifikasi Instrumen dan Emulasi (Tahap 3)

Tanggal: 14 November 2026
Testbed: 2 VM Ubuntu 24.04 (Multipass, driver HCS/Hyper-V), initiator `10.97.0.149`, responder `10.97.0.206`, NIC `eth0`
Perangkat lunak: iproute2 6.1.0 (tc netem), ping dari iputils, strongSwan 6.0.2, OpenSSL 3.5.0
Data mentah: `verifikasi-mtu.txt`, `verifikasi-rtt.txt`, `verifikasi-rtt-ulang10.txt`, `verifikasi-rtt-rapat.txt`, `verifikasi-loss.txt` (folder yang sama)

Tujuan: membuktikan bahwa kondisi jaringan yang diatur (nilai terpasang) benar-benar terjadi (nilai terukur), sesuai subbab "Kalibrasi dan verifikasi instrumen" pada proposal. Toleransi dari proposal: deviasi RTT > 10% memicu pemeriksaan ulang konfigurasi.

## 1. MTU

Metode: `ip link set dev eth0 mtu <N>`, lalu `ping -M do -s <N-28>` (harus berhasil) dan `ping -M do -s <N-27>` (harus ditolak). Dijalankan dari initiator ke responder, tanpa CHILD_SA aktif.

| MTU terpasang | Payload lolos | Hasil | Payload ditolak | Pesan | MTU terukur | Deviasi |
|---|---|---|---|---|---|---|
| 1280 | 1252 | 2/2 diterima, 0% loss, RTT avg 0,43 ms | 1253 | `message too long, mtu=1280` | 1280 | 0 |
| 1400 | 1372 | 2/2 diterima, 0% loss, RTT avg 0,77 ms | 1373 | `message too long, mtu=1400` | 1400 | 0 |
| 1500 | 1472 | 2/2 diterima, 0% loss, RTT avg 0,34 ms | 1473 | `message too long, mtu=1500` | 1500 | 0 |

Catatan:
- Percobaan pertama memberi hasil `mtu=1226/1346/1446` (selisih 54 byte). Penyebabnya CHILD_SA IPsec masih aktif sehingga ping ikut dienkripsi ESP dan overhead ESP memangkas MTU efektif. Pengujian MTU harus dilakukan tanpa SA aktif (`swanctl --terminate --ike net-net` lebih dulu). Overhead ESP sekitar 54 byte ini relevan untuk lalu lintas data, bukan untuk handshake IKE.
- Yang belum dilakukan: konfirmasi ukuran paket pada capture Wireshark untuk tiap MTU (disebut pada proposal).

## 2. RTT (delay)

Metode: `tc qdisc replace dev eth0 root netem delay <RTT/2>` pada kedua VM, lalu `ping` dari initiator ke responder.

| Target RTT | Delay per arah | Jumlah ping dan interval | RTT min (ms) | RTT avg (ms) | RTT max (ms) | mdev (ms) | Deviasi avg terhadap target |
|---|---|---|---|---|---|---|---|
| 10 ms | 5 ms | 100, 0,2 s | 10,516 | 15,003 | 46,739 | 5,330 | +50,0% |
| 10 ms (ulang) | 5 ms | 200, 0,2 s | 10,457 | 14,831 | 53,583 | 5,641 | +48,3% |
| 10 ms (ping rapat) | 5 ms | 500, 0,02 s | 10,357 | 12,920 | 31,994 | 3,605 | +29,2% |
| 50 ms | 25 ms | 100, 0,2 s | 50,492 | 54,882 | 65,836 | 4,494 | +9,8% |
| 100 ms | 50 ms | 100, 0,2 s | 100,508 | 105,943 | 122,702 | 4,986 | +5,9% |

Temuan:
- RTT minimum selalu sama dengan target ditambah sekitar 0,4-0,5 ms (RTT dasar jaringan tanpa netem sekitar 0,3-1,3 ms). Jadi delay netem akurat.
- RTT rata-rata lebih tinggi sekitar 3-6 ms karena jitter pada VM (nilai maksimum jauh di atas rata-rata). Jitter turun ketika ping dikirim lebih rapat, yang menunjukkan sebagian penyebabnya adalah latensi bangun vCPU saat idle.
- Pada level 50 dan 100 ms deviasi rata-rata masih dalam toleransi 10%. Pada level 10 ms deviasi rata-rata melebihi toleransi walaupun RTT minimum akurat.

Keputusan yang perlu dikonfirmasi dengan pembimbing (proposal: deviasi RTT > 10% memicu pemeriksaan ulang):
- Opsi A: diterima dengan dokumentasi (laporkan RTT min dan median, jitter dicatat sebagai keterbatasan validitas).
- Opsi B: kalibrasi delay netem agar RTT rata-rata terukur sama dengan target.

## 3. Packet loss

Metode: `tc qdisc replace dev eth0 root netem loss <p>%` pada initiator saja (agar yang terukur satu arah), lalu `ping -c 2000 -i 0.01` ke responder (ping flood terkontrol).

| Loss terpasang (per arah) | Paket dikirim | Paket diterima | Loss terukur | Selisih |
|---|---|---|---|---|
| 0% (tanpa netem, semua pengujian lain) | 2 sampai 500 | semua | 0% | 0 |
| 1% | 2000 | 1981 | 0,95% | -0,05 poin |
| 5% | 2000 | 1890 | 5,5% | +0,5 poin |

Catatan:
- Pada eksperimen utama netem dipasang di kedua VM sehingga loss berlaku per arah. Loss yang terlihat pada pertukaran dua arah (misalnya ping) kira-kira 1-(1-p)^2, yaitu sekitar 2% untuk p = 1% dan sekitar 9,75% untuk p = 5%. Definisi operasional pada proposal ("per arah") konsisten dengan ini.
- Selisih terukur masih dalam variasi acak model Bernoulli (simpangan baku sekitar 10 paket pada 2000 paket di p = 5%).

## 4. Pengamatan tambahan dari Tahap 2 (bukan hasil eksperimen)

- Handshake hybrid: pesan IKE_INTERMEDIATE yang membawa kunci publik ML-KEM-768 berukuran 1249 byte terfragmentasi menjadi 2 fragmen IKE (paket 1248 byte dan 66 byte). Pengamatan satu run, bukan hasil penelitian.
- IP VM berubah setelah dimatikan dan dinyalakan kembali (`10.97.0.8` dan `10.97.0.13` menjadi `10.97.0.149` dan `10.97.0.206`). Dicatat pada `penyimpangan.md`.

## 5. Status Tahap 3

| Sumbu | Status |
|---|---|
| MTU (1280, 1400, 1500) | Lolos, deviasi 0 |
| Loss (0, 1, 5%) | Lolos |
| RTT (10, 50, 100 ms) | 50 dan 100 ms lolos; 10 ms menunggu keputusan pembimbing (min akurat, avg +29% sampai +50%) |
| Konfirmasi ukuran paket di Wireshark | Belum |
