# Catatan Instalasi Testbed

Dicatat: 14 November 2026. Versi lengkap ada di `versi.md`, topologi di `topologi.md`.

## Urutan langkah (ringkas)
1. Aktifkan Hyper-V dan Virtual Machine Platform di Windows.
2. Pasang Multipass 1.17.0 dan atur driver: `multipass set local.driver=hcs`. Pastikan layanan berjalan: `Start-Service Multipass`.
3. Buat dua VM Ubuntu 24.04 (initiator dan responder), 2 vCPU, 2 GB RAM, 10 GB disk. Waktu tunggu diperpanjang bila perlu (`--timeout 900`). Cocokkan perintah persis dengan riwayat PowerShell-mu.
4. Cek IP: `multipass list`, lalu uji `ping` antar VM.
5. Salin `install.sh` ke kedua VM dan jalankan: `multipass transfer install.sh <vm>:install.sh`, lalu `multipass exec <vm> -- bash install.sh`. Skrip memasang paket dasar, alat ukur, OpenSSL 3.5.0 (ke `/opt/openssl-3.5.0`), dan strongSwan 6.0.2 (dikompilasi dari sumber).
6. Salin `swanctl.conf` ke `/etc/swanctl/swanctl.conf` di tiap VM (izin 600), lalu `sudo swanctl --load-all`.
7. Tes handshake: `sudo swanctl --initiate --child net-net`; cek `IKE_SA ... established` dan `CHILD_SA ... established`.
8. Ganti proposal ke hybrid (`...-x25519-ke1_mlkem768`), muat ulang, ulangi tes.

## Kendala dan solusi
| Kendala | Penyebab | Solusi |
|---|---|---|
| `multipass exec` timeout ke 127.0.0.1 berulang | Driver VirtualBox (NAT, semua VM 10.0.2.15) | Pindah ke driver HCS (Hyper-V) |
| `cannot connect to the multipass socket` | Layanan Multipass `Stopped` | `Start-Service Multipass` lalu tunggu; bila macet, restart Windows |
| `Available disk below minimum` saat membuat VM | Ruang C: kurang | Hapus VM/file tak terpakai, `multipass purge` |
| `cp: cannot stat '/root/swanctl.conf'` | `~` di dalam `sudo bash -c` berarti `/root` | Pakai path lengkap `/home/ubuntu/swanctl.conf` |
| `invalid value for: auth` | Sintaks `;` satu baris di `swanctl.conf` | Satu nilai per baris |
| `multipass: command not found` | Perintah dijalankan di dalam VM | Ketik `exit` lalu jalankan di PowerShell Windows |
| Perintah bash gagal dari PowerShell (`unexpected end of file`) | Tanda kutip ganda di dalam argumen dihapus PowerShell | Gunakan string kutip tunggal tanpa kutip ganda di dalamnya |
| Handshake di loop MTU tampak "berhasil" 8 ms | Output dibuang (`>/dev/null`) dan IP sudah berubah | Selalu tampilkan output; cek IP dengan `multipass list` |
| Ping DF gagal `mtu=1226` pada MTU 1280 | CHILD_SA aktif, ESP memangkas MTU | `swanctl --terminate --ike net-net` sebelum uji MTU |

## Perintah yang sering dipakai
- Status VM: `multipass list`
- Masuk VM: `multipass shell initiator` (keluar: `exit`)
- Mulai/berhenti: `multipass start initiator responder`, `multipass stop initiator responder`
- Handshake: `multipass exec initiator -- sudo swanctl --initiate --child net-net`
- Tutup SA: `multipass exec initiator -- sudo swanctl --terminate --ike net-net`
- Bersihkan netem: `multipass exec <vm> -- sudo tc qdisc del dev eth0 root`
