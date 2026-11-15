# Versi Testbed (isi Tabel 3.6 proposal)

Dicatat: 14 November 2026

## Hardware host
| Komponen | Nilai |
|---|---|
| Laptop/PC | Intel Core i5-8365U @ 1,60 GHz (4 core, 8 prosesor logis) |
| RAM | 15,7 GB |
| OS host | Windows 11 Pro |
| Penyimpanan | SSD; ruang kosong drive C: sempat tersisa sekitar 5-9 GB saat setup (pantau saat eksperimen utama) |

## Hypervisor dan VM
| Komponen | Nilai |
|---|---|
| Orkestrator VM | Multipass 1.17.0+win (multipassd 1.17.0+win) |
| Driver/hypervisor | HCS (Hyper-V Host Compute Service) |
| Mode jaringan | Jaringan default Hyper-V (virtual switch `Default Switch`, NIC `Multipass vNetw`), subnet 10.97.0.0/24, IP dari DHCP |
| Jumlah VM | 2 (initiator dan responder), spesifikasi identik |
| Spesifikasi tiap VM | 2 vCPU, 1,9 GiB RAM (dipesan 2 GB), disk 9,6 GiB |
| Image | Ubuntu 24.04.5 LTS (hash image 04e8f2461a16) |
| Kernel | 6.8.0-147-generic |

## Perangkat lunak di dalam VM
| Kategori | Komponen | Versi |
|---|---|---|
| Library kriptografi | OpenSSL (dikompilasi dari sumber, di `/opt/openssl-3.5.0`) | 3.5.0 (8 Apr 2025), ML-KEM-512/768/1024 tersedia |
| VPN | strongSwan (dikompilasi dari sumber; plugin openssl aktif, plugin gmp dinonaktifkan) | 6.0.2 (swanctl) |
| Emulasi jaringan | iproute2 (`tc netem`) | 6.1.0 (libbpf 1.3.0) |
| Capture | tcpdump | 4.99.4 |
| Analisis paket | TShark (Wireshark) | 4.2.2 |
| Monitoring CPU | pidstat (paket sysstat) | 12.6.1 |
| Pengukuran jaringan | iperf3 | 3.16 |
| Pengukuran jaringan | mtr-tiny, ping (iputils), tracepath | bawaan distribusi |

## Konfigurasi koneksi
- Autentikasi: PSK (keterbatasan dicatat di Bab III).
- Klasik (baseline): `aes256gcm16-prfsha512-x25519`
- Hybrid: `aes256gcm16-prfsha512-x25519-ke1_mlkem768`
- Dikonfirmasi pada log handshake: `selected proposal: IKE:AES_GCM_16_256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_ML_KEM_768`

## Yang masih perlu dicatat nanti
- Versi Python dan pustaka analisis (pandas, scipy, numpy) saat Tahap 7.
- Versi Bash dan skrip orkestrasi saat Tahap 5.
