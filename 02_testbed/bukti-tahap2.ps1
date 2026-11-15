# bukti-tahap2.ps1 - mengumpulkan bukti Tahap 2 testbed PQ-IKEv2
# Jalankan: powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\bukti-tahap2.ps1"
$dl = "$env:USERPROFILE\Downloads"
Start-Transcript -Path "$dl\bukti-tahap2.txt" -Force | Out-Null

function Judul($t) { Write-Host ""; Write-Host "=================================================="; Write-Host $t; Write-Host "==================================================" }
function Run($vm, $cmd) { Write-Host "--- [$vm] ---"; multipass exec $vm -- bash -c $cmd }

Judul "0. INFO HOST & MULTIPASS"
Get-Date
multipass version
multipass get local.driver
multipass list

Judul "1. DUA VM + KONEKTIVITAS (ping dua arah)"
Run initiator 'hostname; ip -br addr show eth0; ping -c 3 10.97.0.13'
Run responder 'hostname; ip -br addr show eth0; ping -c 3 10.97.0.8'

Judul "2. SOFTWARE TERPASANG"
foreach ($vm in @("initiator", "responder")) {
  Run $vm 'uname -r; /opt/openssl-3.5.0/bin/openssl version; /opt/openssl-3.5.0/bin/openssl list -kem-algorithms | grep -i ml-kem-768; sudo swanctl --version 2>&1 | head -1; tcpdump --version 2>&1 | head -1; tshark --version | head -1; pidstat -V 2>&1 | head -1; iperf3 --version | head -1; tc -V; systemctl is-active strongswan; sudo swanctl --list-algs | grep -i -e ml_kem'
}

Judul "3. KONFIGURASI swanctl.conf (PSK disembunyikan)"
Run initiator 'sudo grep -v secret /etc/swanctl/swanctl.conf'
Run responder 'sudo grep -v secret /etc/swanctl/swanctl.conf'

$cap = 'timeout 10 tcpdump -Z root -i eth0 -w /home/ubuntu/{0}.pcap udp port 500 or udp port 4500 2>/dev/null & sleep 2; swanctl --terminate --ike net-net >/dev/null 2>&1; swanctl --initiate --child net-net 2>&1 | grep -i -e selected -e established -e completed; echo; swanctl --list-sas; wait; echo; tshark -r /home/ubuntu/{0}.pcap 2>/dev/null'

Judul "4. HANDSHAKE KLASIK (aes256gcm16-prfsha512-x25519)"
foreach ($vm in @("initiator", "responder")) {
  multipass exec $vm -- sudo sed -i s/-ke1_mlkem768// /etc/swanctl/swanctl.conf
  multipass exec $vm -- sudo swanctl --load-all | Out-Null
}
Run initiator 'grep proposals /etc/swanctl/swanctl.conf'
multipass exec initiator -- sudo bash -c ($cap -f "klasik")

Judul "5. HANDSHAKE HYBRID (aes256gcm16-prfsha512-x25519-ke1_mlkem768)"
foreach ($vm in @("initiator", "responder")) {
  multipass exec $vm -- sudo sed -i 's/x25519$/x25519-ke1_mlkem768/' /etc/swanctl/swanctl.conf
  multipass exec $vm -- sudo swanctl --load-all | Out-Null
}
Run initiator 'grep proposals /etc/swanctl/swanctl.conf'
multipass exec initiator -- sudo bash -c ($cap -f "hybrid")

Judul "6. SALIN FILE REKAMAN KE DOWNLOADS"
multipass transfer initiator:/home/ubuntu/klasik.pcap "$dl\klasik.pcap"
multipass transfer initiator:/home/ubuntu/hybrid.pcap "$dl\hybrid.pcap"
Get-ChildItem "$dl\klasik.pcap", "$dl\hybrid.pcap" | Select-Object Name, Length

Write-Host ""
Write-Host "SELESAI. Bukti tersimpan di: $dl\bukti-tahap2.txt (+ klasik.pcap, hybrid.pcap)"
Stop-Transcript | Out-Null
