# Topologi Testbed

Dicatat: 14 November 2026

## Diagram
```
        Windows 11 Pro (host) - Hyper-V (HCS) - Multipass 1.17.0
        ---------------------------------------------------------
        Default Switch (subnet 10.97.0.0/24, DHCP)

   +----------------------+                 +----------------------+
   |  VM-1: initiator     |   UDP 500/4500  |  VM-2: responder     |
   |  10.97.0.149         | <-------------> |  10.97.0.206         |
   |  eth0                |   IKEv2/IPsec   |  eth0                |
   |  strongSwan 6.0.2    |                 |  strongSwan 6.0.2    |
   |  tc netem + MTU di   |                 |  tc netem di eth0    |
   |  eth0                |                 |                      |
   +----------------------+                 +----------------------+
```

## Detail
| Item | Initiator | Responder |
|---|---|---|
| IP (per 14 Nov 2026) | 10.97.0.149/24 | 10.97.0.206/24 |
| NIC | eth0 | eth0 |
| ID IKE | `initiator` | `responder` |
| Peran | memulai handshake | menjawab handshake |
| Traffic selector | 10.97.0.149/32 === 10.97.0.206/32 | kebalikan |
| Port | UDP 500 (IKE_SA_INIT), UDP 4500 (setelah itu) | idem |

## Cara emulasi jaringan
- Delay dan loss: `tc qdisc replace dev eth0 root netem ...` di **kedua** VM, nilai per arah (delay = RTT/2, loss per arah).
- MTU: `ip link set dev eth0 mtu <N>`.
- Hapus netem: `tc qdisc del dev eth0 root`.

## Catatan penting
- IP berasal dari DHCP dan berubah setelah VM dimatikan lalu dinyalakan lagi (awalnya 10.97.0.8 dan 10.97.0.13). Cek dengan `multipass list` setiap mulai sesi dan perbarui `swanctl.conf` bila berubah.
- Kanal kontrol `multipass exec` lewat jaringan yang sama dengan `eth0`, sehingga netem ikut memperlambatnya (tidak memengaruhi hasil handshake yang diukur lewat swanctl di dalam VM).
- Pengujian MTU dengan ping hanya valid bila tidak ada CHILD_SA aktif (ESP memangkas MTU efektif sekitar 54 byte).
