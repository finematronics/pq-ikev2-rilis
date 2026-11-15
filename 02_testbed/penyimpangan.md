# Catatan Penyimpangan dari Rencana (proposal dan handbook)

Setiap perbedaan antara rencana dan kenyataan dicatat di sini. Tambahkan baris baru setiap ada penyimpangan.

| # | Tanggal | Rencana | Kenyataan | Alasan | Dampak / tindakan |
|---|---|---|---|---|---|
| 1 | 12-13 Nov 2026 | Hypervisor VirtualBox/VMware/WSL2 (Tabel 3.6) | Multipass dengan driver HCS (Hyper-V) | Driver VirtualBox di Multipass deprecated; SSH ke VM terus timeout | Perbarui Tabel 3.6 dan subbab 3.7; konsultasikan ke pembimbing |
| 2 | 13 Nov 2026 | Jaringan internal/bridge antar-VM dengan IP statis (mis. 10.10.0.1/2) | Jaringan default Hyper-V, IP DHCP | Jaringan internal VirtualBox tidak lagi dipakai | IP tidak tetap (lihat #3) |
| 3 | 14 Nov 2026 | IP VM stabil | IP berubah setelah VM dimatikan: .8/.13 menjadi .149/.206 | DHCP tidak menjamin IP sama | Perbarui `swanctl.conf`; jangan matikan VM selama eksperimen utama, atau pasang IP tetap sebelum Tahap 5 |
| 4 | 13 Nov 2026 | Handbook membolehkan 3 VM (dengan router) | 2 VM tanpa router | Sesuai desain utama proposal | Tidak ada |
| 5 | 13 Nov 2026 | Sintaks `swanctl.conf` satu baris dengan `;` (handbook) | Satu nilai per baris | Sintaks `;` menghasilkan error `invalid value for: auth` | Format baru dipakai di semua file |
| 6 | 13 Nov 2026 | Proposal hybrid `x25519-mlkem768` (handbook) | `x25519-ke1_mlkem768` | Sintaks multiple key exchange (RFC 9370) di strongSwan 6.0 memakai `ke1_`; sintaks lama berarti alternatif, bukan hybrid | Perbarui definisi konfigurasi hybrid (Tabel 3.7) dan skrip eksperimen |
| 7 | 13 Nov 2026 | Konfigurasi tidak menuliskan alamat | Ditambah `local_addrs` dan `remote_addrs` | Agar koneksi jelas antara dua IP | Format baru |
| 8 | 14 Nov 2026 | Uji MTU dengan ping DF | Harus dilakukan tanpa CHILD_SA aktif | ESP memangkas MTU efektif sekitar 54 byte; uji pertama memberi `mtu=1226/1346/1446` | Tambahkan `swanctl --terminate` sebelum uji MTU |
| 9 | 14 Nov 2026 | Toleransi RTT +-10% | Level 10 ms: RTT min akurat tapi rata-rata +29% sampai +50% | Jitter VM (latensi bangun vCPU) | **Menunggu keputusan pembimbing**: diterima dengan dokumentasi (lapor min/median) atau kalibrasi delay |
| 10 | 14 Nov 2026 | Verifikasi loss | Netem dipasang di satu arah (initiator) | Agar loss terukur satu arah dan bisa dibandingkan langsung | Eksperimen utama tetap dua arah (per arah), sesuai proposal |
| 11 | 13-14 Nov 2026 | Layanan Multipass stabil | Layanan sempat `Stopped` setelah komputer lama dipakai, socket tidak bisa dihubungi | Daemon macet | Restart Windows lalu `multipass list`; data VM tetap aman |
