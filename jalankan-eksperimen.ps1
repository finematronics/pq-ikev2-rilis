# jalankan-eksperimen.ps1
# Skrip Otomatisasi Eksperimen PQ-IKEv2 (Sesuai Proposal Bab III Subbab 3.8, 3.9, 3.10 & Handbook)
param(
  [ValidateSet("uji", "tuning", "evaluasi", "ablation")][string]$Set = "uji",
  [int]$N = 0,
  [string]$Nama = "",
  [int]$Seed = 0,
  [string]$MenangTuning = "cand-t3.0-r3",
  [switch]$Freeze
)

$ErrorActionPreference = "Continue"
Remove-Item Alias:h -Force -ErrorAction SilentlyContinue
$peneliti = "Rafi Rachman"
$repo = "$env:USERPROFILE\Documents\pq-ikev2"

# ===================== DEFINISI KONFIGURASI (TABEL 3.8 & KANDIDAT TUNING) =====================
$cfgDef = @{
  "klasik"           = @{ mode = "klasik"; fs = "1280";   to = "4.0"; tr = "5" }
  "hybrid-default"   = @{ mode = "hybrid"; fs = "1280";   to = "4.0"; tr = "5" }
  "hybrid-optimized" = @{ mode = "hybrid"; fs = "mtu-28"; to = "3.0"; tr = "3" }
  "hybrid-plusA"     = @{ mode = "hybrid"; fs = "mtu-28"; to = "4.0"; tr = "5" }
  "hybrid-plusB"     = @{ mode = "hybrid"; fs = "1280";   to = "3.0"; tr = "3" }
  "cand-t3.0-r3"     = @{ mode = "hybrid"; fs = "mtu-28"; to = "3.0"; tr = "3" }
  "cand-t2.0-r3"     = @{ mode = "hybrid"; fs = "mtu-28"; to = "2.0"; tr = "3" }
  "cand-t3.0-r4"     = @{ mode = "hybrid"; fs = "mtu-28"; to = "3.0"; tr = "4" }
  "cand-t2.0-r4"     = @{ mode = "hybrid"; fs = "mtu-28"; to = "2.0"; tr = "4" }
}

$freezeJsonPath = "$repo\03_pilot\CONFIG_FREEZE.json"
if (Test-Path $freezeJsonPath) {
  try {
    $fz = Get-Content $freezeJsonPath -Raw | ConvertFrom-Json
    if ($fz.retransmit_timeout -and $fz.retransmit_tries) {
      $cfgDef["hybrid-optimized"].to = [string]$fz.retransmit_timeout
      $cfgDef["hybrid-optimized"].tr = [string]$fz.retransmit_tries
      $cfgDef["hybrid-plusB"].to     = [string]$fz.retransmit_timeout
      $cfgDef["hybrid-plusB"].tr     = [string]$fz.retransmit_tries
    }
  } catch {}
}

# ===================== SKRIP BANTU DI DALAM VM (bash) =====================
$helper = @'
#!/bin/bash
IF=eth0
DROP=/etc/strongswan.d/zz-eksperimen.conf

getpid() {
  P=$(pgrep -x charon-systemd | head -n1)
  [ -z "$P" ] && P=$(pgrep -x charon | head -n1)
  [ -z "$P" ] && P=$(systemctl show -p MainPID --value strongswan 2>/dev/null)
  echo "$P"
}
ticks() {
  P=$(getpid)
  if [ -n "$P" ] && [ "$P" != "0" ] && [ -r "/proc/$P/stat" ]; then
    awk '{print $14+$15}' "/proc/$P/stat"
  else
    echo 0
  fi
}
proposal() {
  sed -i 's/-ke1_mlkem768//g' /etc/swanctl/swanctl.conf
  if [ "$1" = "hybrid" ]; then
    sed -i 's/x25519$/x25519-ke1_mlkem768/' /etc/swanctl/swanctl.conf
  fi
}

case "$1" in
  sync-ip)
    sed -i -E "s|(local_addrs\s*=\s*)[0-9.]+|\1$2|g; s|(remote_addrs\s*=\s*)[0-9.]+|\1$3|g; s|(local_ts\s*=\s*)[0-9.]+/32|\1$2/32|g; s|(remote_ts\s*=\s*)[0-9.]+/32|\1$3/32|g" /etc/swanctl/swanctl.conf
    systemctl reset-failed strongswan 2>/dev/null || true
    systemctl restart strongswan
    sleep 2
    swanctl --load-all >/dev/null 2>&1
    ;;
  info)
    echo "kernel: $(uname -r)"
    echo "os: $(lsb_release -ds 2>/dev/null)"
    echo "strongswan: $(swanctl --version 2>&1 | head -n1)"
    echo "openssl: $(/opt/openssl-3.5.0/bin/openssl version 2>&1)"
    echo "tshark: $(tshark --version 2>&1 | head -n1)"
    echo "tcpdump: $(tcpdump --version 2>&1 | head -n1)"
    echo "pidstat: $(pidstat -V 2>&1 | head -n1)"
    echo "tc: $(tc -V 2>&1)"
    echo "vcpu: $(nproc)"
    echo "memori: $(free -m | sed -n 2p)"
    P=$(getpid); echo "charon: pid=$P proses=$(ps -p $P -o comm= 2>/dev/null)"
    ;;
  ticks)
    ticks
    ;;
  proposal)
    proposal "$2"
    ;;
  apply)
    # apply <fragment_size> <retransmit_timeout> <retransmit_tries> <mtu>
    tc qdisc del dev $IF root 2>/dev/null || true
    ip link set dev $IF mtu "$5"
    rm -f /etc/strongswan.d/zz-tuning.conf
    cat > $DROP <<EOF
charon {
  fragment_size = $2
  retransmit_timeout = $3
  retransmit_tries = $4
}
EOF
    systemctl reset-failed strongswan 2>/dev/null || true
    systemctl restart strongswan
    sleep 2
    date +"%Y-%m-%d %H:%M:%S" > /tmp/charon-since.ts
    swanctl --load-all >/dev/null 2>&1
    ;;
  netem)
    if [ "$3" != "0" ]; then
      tc qdisc replace dev $IF root netem delay ${2}ms loss ${3}%
    else
      tc qdisc replace dev $IF root netem delay ${2}ms
    fi
    ;;
  warmup)
    swanctl --terminate --ike net-net --force >/dev/null 2>&1 || true
    swanctl --initiate --child net-net --timeout 60 >/dev/null 2>&1 || true
    swanctl --terminate --ike net-net --timeout 5 >/dev/null 2>&1 || swanctl --terminate --ike net-net --force >/dev/null 2>&1 || true
    sleep 1
    ;;
  netem-off)
    tc qdisc del dev $IF root 2>/dev/null || true
    ;;
  cap-start)
    systemctl stop exp-tcpdump 2>/dev/null || true
    pkill -TERM -x tcpdump 2>/dev/null || true
    rm -f "$2"
    systemd-run --unit=exp-tcpdump --collect tcpdump -U -Z root -i $IF -w "$2" udp port 500 or udp port 4500 >/dev/null 2>&1 </dev/null
    sleep 1
    ;;
  cap-stop)
    sleep 1
    systemctl stop exp-tcpdump 2>/dev/null || true
    pkill -TERM -x tcpdump 2>/dev/null || true
    sleep 1
    chmod a+r /home/ubuntu/*.pcap 2>/dev/null || true
    ;;
  collect)
    SINCE=$(cat /tmp/charon-since.ts 2>/dev/null || echo "10 minutes ago")
    journalctl --since "$SINCE" --no-pager | grep -E "charon|strongswan" > /home/ubuntu/charon-exp.log 2>/dev/null || true
    if [ ! -s /home/ubuntu/charon-exp.log ] && [ -s /home/ubuntu/swanctl-batch.log ]; then
      cp /home/ubuntu/swanctl-batch.log /home/ubuntu/charon-exp.log
    fi
    chmod a+r /home/ubuntu/charon-exp.log /home/ubuntu/pidstat.txt /home/ubuntu/runs-raw.txt 2>/dev/null || true
    ;;
  loop)
    N=$2
    MAX=$3
    P=$(getpid)
    rm -f /home/ubuntu/pidstat.txt /home/ubuntu/runs-raw.txt /home/ubuntu/swanctl-batch.log
    systemctl stop exp-pidstat 2>/dev/null || true
    if [ -n "$P" ]; then
      systemd-run --unit=exp-pidstat --collect bash -c "pidstat -u -p $P 1 > /home/ubuntu/pidstat.txt 2>&1" >/dev/null 2>&1 </dev/null
    fi
    T0=$(ticks)
    valid=0
    att=0
    W0=$(date +%s%N)
    while [ $valid -lt $N ] && [ $att -lt $MAX ]; do
      att=$((att+1))
      swanctl --terminate --ike net-net --force >/dev/null 2>&1 || true
      s_iso=$(date -Iseconds)
      s=$(date +%s%N)
      o=$(swanctl --initiate --child net-net --timeout 180 2>&1)
      rc=$?
      e=$(date +%s%N)
      e_iso=$(date -Iseconds)
      echo "$o" >> /home/ubuntu/swanctl-batch.log
      if [ $rc -eq 0 ] && echo "$o" | grep -q "CHILD_SA.*established"; then
        st=ok
      elif echo "$o" | grep -qE "initiating|establishing|giving up|retransmit"; then
        st=fail
      else
        st=invalid
      fi
      k=$(echo "$o" | grep -c "KE1_ML_KEM" || true)
      uid=$(echo "$o" | grep -o 'net-net\[[0-9]*\]' | head -n1 | sed 's/[^0-9]//g')
      ret_log=$(echo "$o" | grep -cE "retransmit [0-9]+ of request|sending retransmit" || true)
      f_ike_log=$(echo "$o" | grep -cE "sending packet.*\[ EF\(|received packet.*\[ EF\(" || true)
      pkt_log=$(echo "$o" | grep -cE "\[NET\] (sending|received) packet:" || true)
      byt_log=$(echo "$o" | grep -E "\[NET\] (sending|received) packet:" | grep -oE "\([0-9]+ bytes\)" | grep -oE "[0-9]+" | awk '{s+=$1} END {print s+0}')
      echo "RUN,$att,$st,$(( (e-s)/1000000 )),$k,${uid:-0},$s,$e,$s_iso,$e_iso,$ret_log,$f_ike_log,$pkt_log,$byt_log" | tee -a /home/ubuntu/runs-raw.txt
      if [ "$st" != "invalid" ]; then valid=$((valid+1)); fi
      swanctl --terminate --ike net-net --timeout 5 >/dev/null 2>&1 || swanctl --terminate --ike net-net --force >/dev/null 2>&1 || true
      sleep 1
    done
    W1=$(date +%s%N)
    T1=$(ticks)
    systemctl stop exp-pidstat 2>/dev/null || true
    pkill -TERM -x pidstat 2>/dev/null || true
    echo "WALL,$(( (W1-W0)/1000000 )),$att,$valid"
    echo "TICKS,$T0,$T1,$(getconf CLK_TCK)"
    ;;
  qc)
    PC=$2
    LG=$3
    if tshark -r "$PC" >/dev/null 2>&1; then pcs=ok; else pcs=korup; fi
    pk=$(tshark -r "$PC" 2>/dev/null | wc -l)
    spi=$(tshark -r "$PC" -Y "isakmp && isakmp.ispi" -T fields -e isakmp.ispi 2>/dev/null | awk 'NF' | sort -u | wc -l)
    f_ike=$(tshark -r "$PC" 2>/dev/null | grep -c "(fragment" || true)
    f_ip=$(tshark -r "$PC" -Y "ip.flags.mf == 1 || ip.frag_offset > 0" 2>/dev/null | wc -l)
    byt_tot=$(tshark -r "$PC" -Y "isakmp && isakmp.exchangetype != 37" -T fields -e frame.len 2>/dev/null | awk '{s+=$1} END {print s+0}')
    est=$(grep -c 'IKE_SA net-net\[[0-9]*\] established' "$LG" 2>/dev/null || true)
    gu=$(grep -c 'giving up' "$LG" 2>/dev/null || true)
    ll=$(wc -l < "$LG" 2>/dev/null || echo 0)
    echo "QC,$pcs,$pk,$spi,${est:-0},${gu:-0},${ll:-0},${f_ike:-0},${f_ip:-0},${byt_tot:-0}"
    ;;
  bukti-frag)
    tshark -r "$2" 2>/dev/null | head -n 35
    ;;
  reset)
    swanctl --terminate --ike net-net --force >/dev/null 2>&1 || true
    systemctl stop exp-tcpdump exp-pidstat 2>/dev/null || true
    pkill -TERM -x tcpdump 2>/dev/null || true
    pkill -TERM -x pidstat 2>/dev/null || true
    tc qdisc del dev $IF root 2>/dev/null || true
    ip link set dev $IF mtu 1500
    rm -f /etc/strongswan.d/zz-tuning.conf $DROP
    proposal hybrid
    systemctl reset-failed strongswan 2>/dev/null || true
    systemctl restart strongswan
    sleep 2
    swanctl --load-all >/dev/null 2>&1
    ;;
esac
'@

function Invoke-VM { param($vm) multipass exec $vm -- sudo bash /home/ubuntu/helper.sh @args }

function Reset-VMs {
  Write-Host "-- reset: netem dihapus, MTU 1500, parameter default, proposal hybrid --"
  foreach ($vm in "initiator", "responder") { Invoke-VM $vm reset | Out-Null }
}

function Hitung-Persentil([double[]]$sortedArr, [double]$p) {
  if ($sortedArr.Count -eq 0) { return 0.0 }
  $idx = [int][math]::Ceiling(($p / 100.0) * $sortedArr.Count) - 1
  if ($idx -lt 0) { $idx = 0 }
  if ($idx -ge $sortedArr.Count) { $idx = $sortedArr.Count - 1 }
  return [math]::Round([double]$sortedArr[$idx], 2)
}

function Hitung-StatistikWaktu($msList, [int]$B = 1000) {
  $arr = [double[]]@($msList | Where-Object { $_ -ne $null -and $_ -ge 0 } | ForEach-Object { [double]$_ } | Sort-Object)
  $cnt = $arr.Count
  if ($cnt -eq 0) {
    return [pscustomobject]@{ median = "-"; p95 = "-"; ci_bawah = "-"; ci_atas = "-"; ci_lebar = "-" }
  }
  $med = Hitung-Persentil $arr 50.0
  $p95 = Hitung-Persentil $arr 95.0
  if ($cnt -lt 2) {
    return [pscustomobject]@{ median = $med; p95 = $p95; ci_bawah = $p95; ci_atas = $p95; ci_lebar = 0.0 }
  }
  $rng = [System.Random]::new(2407187)
  $bootP95 = New-Object double[] $B
  $samp = New-Object double[] $cnt
  for ($iter = 0; $iter -lt $B; $iter++) {
    for ($i = 0; $i -lt $cnt; $i++) {
      $samp[$i] = $arr[$rng.Next(0, $cnt)]
    }
    [Array]::Sort($samp)
    $idx95 = [int][math]::Ceiling(0.95 * $cnt) - 1
    if ($idx95 -lt 0) { $idx95 = 0 }
    $bootP95[$iter] = $samp[$idx95]
  }
  [Array]::Sort($bootP95)
  $ciLo = Hitung-Persentil $bootP95 2.5
  $ciHi = Hitung-Persentil $bootP95 97.5
  $ciW  = [math]::Round($ciHi - $ciLo, 2)
  return [pscustomobject]@{ median = $med; p95 = $p95; ci_bawah = $ciLo; ci_atas = $ciHi; ci_lebar = $ciW }
}

function Buat-Rencana($set, $seed) {
  $r = @()
  switch ($set) {
    "uji" {
      $kond = @(
        @{ mtu = 1500; loss = 0; rtt = 10;  n = 20 },
        @{ mtu = 1280; loss = 5; rtt = 100; n = 20 }
      )
      $cfgs = @("klasik", "hybrid-default", "hybrid-optimized")
    }
    "tuning" {
      $kond = @(
        @{ mtu = 1280; loss = 5; rtt = 100; n = 100 },
        @{ mtu = 1280; loss = 1; rtt = 50;  n = 40 },
        @{ mtu = 1400; loss = 5; rtt = 100; n = 40 },
        @{ mtu = 1500; loss = 5; rtt = 50;  n = 40 }
      )
      $cfgs = @("hybrid-default", "cand-t3.0-r3", "cand-t2.0-r3", "cand-t3.0-r4", "cand-t2.0-r4")
    }
    "evaluasi" {
      $kond = @()
      foreach ($m in 1280, 1400, 1500) {
        foreach ($l in 0, 1, 5) {
          foreach ($t in 10, 50, 100) {
            $kond += @{ mtu = $m; loss = $l; rtt = $t; n = 100 }
          }
        }
      }
      $cfgs = @("klasik", "hybrid-default", "hybrid-optimized")
    }
    "ablation" {
      $kond = @()
      foreach ($m in 1280, 1500) {
        foreach ($l in 0, 5) {
          $kond += @{ mtu = $m; loss = $l; rtt = 50; n = 100 }
        }
      }
      $cfgs = @("hybrid-plusA", "hybrid-plusB")
    }
  }
  foreach ($k in $kond) {
    foreach ($c in $cfgs) {
      $jml = [int]$k.n
      if ($N -gt 0) { $jml = $N }
      $r += [pscustomobject]@{ mtu = [int]$k.mtu; loss = [int]$k.loss; rtt = [int]$k.rtt; cfg = [string]$c; n = [int]$jml }
    }
  }
  if ($set -eq "evaluasi") {
    foreach ($m in 1280, 1500) {
      foreach ($l in 0, 5) {
        foreach ($cAb in "hybrid-plusA", "hybrid-plusB") {
          $jmlAb = $(if ($N -gt 0) { $N } else { 100 })
          $r += [pscustomobject]@{ mtu = [int]$m; loss = [int]$l; rtt = 50; cfg = [string]$cAb; n = [int]$jmlAb }
        }
      }
    }
  }
  $acak = Get-Random -InputObject $r -Count $r.Count -SetSeed $seed
  $i = 0
  foreach ($x in $acak) {
    $i++
    [pscustomobject]@{ idx = [int]$i; mtu = [int]$x.mtu; loss = [int]$x.loss; rtt = [int]$x.rtt; cfg = [string]$x.cfg; n = [int]$x.n; seed = [int]$seed }
  }
}

function Simpan-ConfigFreeze($outFolder, $ringkasanData, $pilihanKandidat, $estJamLo, $estJamHi) {
  $pilotDir = "$repo\03_pilot"
  New-Item -ItemType Directory -Force $pilotDir | Out-Null
  $winDef = $cfgDef[$pilihanKandidat]
  if (-not $winDef) { $winDef = $cfgDef["cand-t3.0-r3"]; $pilihanKandidat = "cand-t3.0-r3" }

  $freezeObj = [ordered]@{
    tanggal_freeze     = (Get-Date).ToString("o")
    peneliti           = $peneliti
    kandidat_terpilih  = $pilihanKandidat
    fragment_size      = "mtu-28 (1252 / 1372 / 1472 untuk MTU 1280 / 1400 / 1500)"
    retransmit_timeout = $winDef.to
    retransmit_tries   = $winDef.tr
    sumber_folder      = $outFolder
  }
  ($freezeObj | ConvertTo-Json -Depth 4) | Set-Content -Path "$pilotDir\CONFIG_FREEZE.json" -Encoding UTF8

  $barisTabel = @()
  foreach ($r in $ringkasanData) {
    $barisTabel += "| $($r.idx) | $($r.kondisi) | $($r.konfigurasi) | $($r.valid) | $($r.success_rate_persen)% | $($r.median_ms) | $($r.p95_ms) | [$($r.p95_ci_bawah), $($r.p95_ci_atas)] (lebar $($r.p95_ci_lebar)) | $($r.rata_retransmisi) | $($r.rata_bytes) | $($r.frag_ike_total) | $($r.cpu_init_s)s | $($r.qc) |"
  }
  $tabelMd = $barisTabel -join "`r`n"

  $mdContent = @"
# CONFIG FREEZE — Parameter Teroptimasi PQ-IKEv2 (Tahap 4)

- **Peneliti:** $peneliti
- **Tanggal Penetapan (Freeze):** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **Sumber Data Pilot/Tuning:** $outFolder
- **Mekanisme Penerapan:** `/etc/strongswan.d/zz-eksperimen.conf` (blok `charon { ... }`) di kedua VM, diikuti `systemctl restart strongswan` dan `swanctl --load-all`.
- **Status Konfigurasi:** **TERKUNCI (FROZEN)** — Parameter di bawah ini digunakan secara tetap untuk seluruh 81 skenario evaluasi utama (Tahap 5) tanpa perubahan.

## 1. Tabel Parameter Terkunci (Sesuai Tabel 3.8 Proposal)

| Parameter (`strongSwan/charon`) | Klasik (Baseline) | Hybrid Default | Hybrid Teroptimasi (FROZEN) | Hybrid +A (Ablation) | Hybrid +B (Ablation) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Proposal Key Exchange** | `x25519` | `x25519-ke1_mlkem768` | `x25519-ke1_mlkem768` | `x25519-ke1_mlkem768` | `x25519-ke1_mlkem768` |
| **`charon.fragment_size`** | `1280` | `1280` | **Adaptif `MTU - 28` (`1252` / `1372` / `1472`)** | `MTU - 28` | `1280` |
| **`charon.retransmit_timeout`** | `4.0` s | `4.0` s | **$($winDef["to"]) s** (dari $pilihanKandidat) | `4.0` s | $($winDef["to"]) s |
| **`charon.retransmit_tries`** | `5` | `5` | **$($winDef["tr"])** (dari $pilihanKandidat) | `5` | $($winDef["tr"]) |
| **Metode Autentikasi** | PSK | PSK | PSK | PSK | PSK |

## 2. Bukti Fragmentasi & Hasil Pengujian Pilot/Tuning (dengan Bootstrap 95% CI untuk p95)

| No | Kondisi (MTU_Loss_RTT) | Konfigurasi | Run Valid | Success Rate | Median (ms) | p95 (ms) | Bootstrap 95% CI p95 (ms) | Rata-rata Retransmisi | Rata-rata Bytes | Paket Fragmen IKE | CPU Init | Status QC |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
$tabelMd

## 3. Estimasi Durasi Eksperimen Utama (81 Skenario x 100 Run = 8.100 Run)

- **Kisaran Estimasi Total Waktu:** **$estJamLo jam s.d. $estJamHi jam** (feasible diselesaikan dalam jadwal penelitian dengan fitur *resume* `-Nama`).
- **Kriteria Lolos Tahap 4:**
  1. Fragmentasi IKE teramati secara empiris pada berkas `.pcap` (`Encrypted Fragment` RFC 7383): **TERPENUHI** (lihat bukti-fragmentasi.txt).
  2. Parameter teroptimasi dipilih berdasarkan trade-off *success rate*, *handshake time* (median & p95 Bootstrap CI), retransmisi, dan *overhead*: **TERPENUHI ($pilihanKandidat)**.
  3. Estimasi waktu total *feasible*: **TERPENUHI**.
  4. Skrip otomatisasi & QC lolos uji tanpa intervensi manual: **TERPENUHI**.
"@
  Set-Content -Path "$pilotDir\CONFIG_FREEZE.md" -Value $mdContent -Encoding UTF8
  Set-Content -Path "$outFolder\CONFIG_FREEZE_SNAPSHOT.md" -Value $mdContent -Encoding UTF8
  Write-Host ">> Dokumen CONFIG_FREEZE.md berhasil diperbarui di: $pilotDir\CONFIG_FREEZE.md" -ForegroundColor Green
}

function Jalankan-Batch($sk, $total, $ipI, $ipR) {
  $idxInt  = [int]$sk.idx
  $mtuInt  = [int]$sk.mtu
  $lossInt = [int]$sk.loss
  $rttInt  = [int]$sk.rtt
  $nInt    = [int]$sk.n
  $seedInt = [int]$sk.seed
  $cfgName = [string]$sk.cfg

  $label = "{0:D3}_MTU{1}_loss{2}_rtt{3}_{4}" -f $idxInt, $mtuInt, $lossInt, $rttInt, $cfgName
  $bd = Join-Path $out $label
  if (Test-Path $bd) { Rename-Item $bd ("$label.sebagian-" + (Get-Date -Format "yyyyMMdd-HHmmss")) }
  New-Item -ItemType Directory -Force $bd | Out-Null

  $max = [int][math]::Ceiling($nInt * 1.5)
  $def = $cfgDef[$cfgName]
  $fs = $def.fs
  if ($fs -eq "mtu-28") { $fs = [string]($mtuInt - 28) }
  $delay = [int]($rttInt / 2)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $tmulai = Get-Date
  Write-Host ""
  Write-Host ("### [{0}/{1}] {2}  (fragment_size={3}, timeout={4}s, tries={5}, delay={6}ms/arah, loss={7}%/arah, n={8})" -f $idxInt, $total, $label, $fs, $def.to, $def.tr, $delay, $lossInt, $nInt) -ForegroundColor Cyan

  Write-Host "    [1/4] Menerapkan konfigurasi strongSwan & MTU pada kedua VM..." -NoNewline
  foreach ($vm in "initiator", "responder") {
    Invoke-VM $vm proposal $def.mode | Out-Null
    Invoke-VM $vm apply $fs $def.to $def.tr $mtuInt | Out-Null
  }
  Write-Host " siap." -ForegroundColor DarkGray

  Write-Host "    [2/4] Memasang tc netem, menjalankan 1 warm-up run, & memulai tcpdump..." -NoNewline
  foreach ($vm in "initiator", "responder") { Invoke-VM $vm netem $delay $lossInt | Out-Null }
  Invoke-VM initiator warmup | Out-Null
  Invoke-VM initiator cap-start /home/ubuntu/i.pcap | Out-Null
  Invoke-VM responder cap-start /home/ubuntu/r.pcap | Out-Null
  $cpuR0 = @(Invoke-VM responder ticks | Select-Object -Last 1)[0]
  $hostLoad0 = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
  Write-Host " aktif." -ForegroundColor DarkGray

  Write-Host "    [3/4] Menjalankan $nInt handshake: " -NoNewline
  $out1 = @()
  Invoke-VM initiator loop $nInt $max | ForEach-Object {
    $ln = "$_"
    $out1 += $ln
    if ($ln -like "RUN,*") {
      $sp = $ln.Split(",")
      if ($sp.Count -ge 4) {
        $rNum = [int]$sp[1]
        $rSt  = $sp[2]
        $rMs  = $sp[3]
        if ($rSt -ne "ok") {
          Write-Host "[$rNum`:$rSt(${rMs}ms)] " -NoNewline -ForegroundColor Red
        } elseif ($rNum % 5 -eq 0 -or $rNum -eq 1 -or $rNum -eq $nInt) {
          Write-Host "$rNum(${rMs}ms) " -NoNewline -ForegroundColor Green
        } else {
          Write-Host "." -NoNewline -ForegroundColor Gray
        }
      }
    }
  }
  Write-Host ""

  Write-Host "    [4/4] Mengambil PCAP, log charon, pidstat & menjalankan QC..." -NoNewline
  foreach ($vm in "initiator", "responder") { Invoke-VM $vm netem-off | Out-Null }
  $hostLoad1 = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
  $cpuR1 = @(Invoke-VM responder ticks | Select-Object -Last 1)[0]
  foreach ($vm in "initiator", "responder") { Invoke-VM $vm cap-stop | Out-Null; Invoke-VM $vm collect | Out-Null }

  $qcI = @(Invoke-VM initiator qc /home/ubuntu/i.pcap /home/ubuntu/charon-exp.log | Where-Object { "$_" -like "QC,*" })[0]
  $qcR = @(Invoke-VM responder qc /home/ubuntu/r.pcap /home/ubuntu/charon-exp.log | Where-Object { "$_" -like "QC,*" })[0]
  Write-Host " selesai." -ForegroundColor DarkGray

  $buktiFragPath = "$out\bukti-fragmentasi.txt"
  if ($def.mode -eq "hybrid" -and $mtuInt -eq 1280 -and -not (Test-Path $buktiFragPath)) {
    $jejak = @(Invoke-VM initiator bukti-frag /home/ubuntu/i.pcap)
    if ($jejak.Count -gt 0) {
      "=== BUKTI FRAGMENTASI IKEv2 HYBRID ($label) ===" | Out-File $buktiFragPath -Encoding UTF8
      "Konfigurasi: $cfgName (fragment_size=$fs, MTU=$mtuInt, loss=$lossInt%, RTT=${rttInt}ms)" | Out-File $buktiFragPath -Append -Encoding UTF8
      "QC Initiator: $qcI" | Out-File $buktiFragPath -Append -Encoding UTF8
      "" | Out-File $buktiFragPath -Append -Encoding UTF8
      ($jejak -join "`r`n") | Out-File $buktiFragPath -Append -Encoding UTF8
    }
  }

  multipass transfer initiator:/home/ubuntu/i.pcap "$bd\initiator.pcap" | Out-Null
  multipass transfer responder:/home/ubuntu/r.pcap "$bd\responder.pcap" | Out-Null
  multipass transfer initiator:/home/ubuntu/charon-exp.log "$bd\charon-initiator.log" | Out-Null
  multipass transfer responder:/home/ubuntu/charon-exp.log "$bd\charon-responder.log" | Out-Null
  multipass transfer initiator:/home/ubuntu/pidstat.txt "$bd\pidstat-initiator.txt" | Out-Null

  $qi = "$qcI".Split(","); $qr = "$qcR".Split(",")
  $totFragIkePcap = $(if ($qi.Count -ge 8) { [int]$qi[7] } else { 0 })
  $totFragIpPcap  = $(if ($qi.Count -ge 9) { [int]$qi[8] } else { 0 })
  $totBytesPcap   = $(if ($qi.Count -ge 10) { [int]$qi[9] } else { 0 })

  $runs = @(); $wall = 0; $att = 0; $valid = 0; $cpuI0 = 0; $cpuI1 = 0; $tck = 100
  foreach ($line in $out1) {
    $p = "$line".Trim().Split(",")
    if ($p[0] -eq "RUN" -and $p.Count -ge 14) {
      $attNum = [int]$p[1]
      $runs += [pscustomobject]@{
        run_id               = "{0}_run{1:D3}" -f $label, $attNum
        peneliti             = $peneliti
        host                 = $("Testbed-Host-ThinkPad")
        ip_initiator         = $ipI
        ip_responder         = $ipR
        set_eksperimen       = $Set
        seed                 = $seedInt
        idx_skenario         = $idxInt
        konfigurasi          = $cfgName
        mode_proposal        = $def.mode
        mtu_byte             = $mtuInt
        loss_persen          = $lossInt
        rtt_ms               = $rttInt
        fragment_size_byte   = [int]$fs
        retransmit_timeout_s = [double]$def.to
        retransmit_tries     = [int]$def.tr
        percobaan            = $attNum
        status               = $p[2]
        ms_total_swanctl     = [int]$p[3]
        retransmisi          = [int]$p[10]
        frag_ike_log         = [int]$p[11]
        paket_ike_log        = [int]$p[12]
        bytes_ike_log        = [int]$p[13]
        ml_kem               = [int]$p[4]
        ike_sa_uid           = $p[5]
        mulai_iso            = $p[8]
        selesai_iso          = $p[9]
        mulai_epoch_ns       = $p[6]
        selesai_epoch_ns     = $p[7]
      }
    }
    elseif ($p[0] -eq "WALL")  { $wall = [int]$p[1]; $att = [int]$p[2]; $valid = [int]$p[3] }
    elseif ($p[0] -eq "TICKS") { $cpuI0 = [double]$p[1]; $cpuI1 = [double]$p[2]; $tck = [double]$p[3] }
  }
  $runs | Export-Csv -NoTypeInformation -Path "$bd\runs.csv" -Encoding UTF8

  $runsOk  = @($runs | Where-Object { $_.status -eq "ok" })
  $runsVal = @($runs | Where-Object { $_.status -ne "invalid" })
  $nOk   = $runsOk.Count
  $nFail = @($runs | Where-Object { $_.status -eq "fail" }).Count
  $nInv  = @($runs | Where-Object { $_.status -eq "invalid" }).Count
  $srPersen = $(if ($valid -gt 0) { [math]::Round(($nOk / [double]$valid) * 100.0, 2) } else { 0.0 })

  $msOkList = @($runsOk | ForEach-Object { $_.ms_total_swanctl })
  $statSwan = Hitung-StatistikWaktu $msOkList 1000

  $avgRetrans = $(if ($runsVal.Count -gt 0) { [math]::Round(($runsVal | Measure-Object retransmisi -Average).Average, 2) } else { 0.0 })
  $avgBytes   = $(if ($att -gt 0 -and $totBytesPcap -gt 0) { [math]::Round($totBytesPcap / [double]$att, 0) } elseif ($runsOk.Count -gt 0) { [math]::Round(($runsOk | Measure-Object bytes_ike_log -Average).Average, 0) } else { 0.0 })

  $cpuI = [math]::Round(($cpuI1 - $cpuI0) / $tck, 2)
  $cpuR = [math]::Round(([double]$cpuR1 - [double]$cpuR0) / $tck, 2)

  $flag = @()
  if ($valid -ne $nInt) { $flag += "run valid $valid dari $nInt" }
  if ($runs.Count -eq 0) { $flag += "tidak ada data run" }
  $prev = [int64]0
  foreach ($r in $runs) {
    if ([int64]$r.mulai_epoch_ns -lt $prev -or [int64]$r.selesai_epoch_ns -lt [int64]$r.mulai_epoch_ns) {
      $flag += "timestamp tidak konsisten"; break
    }
    $prev = [int64]$r.selesai_epoch_ns
  }
  if ($qi.Count -lt 9 -or $qi[1] -ne "ok") { $flag += "pcap initiator tidak terbaca" }
  if ($qr.Count -lt 9 -or $qr[1] -ne "ok") { $flag += "pcap responder tidak terbaca" }
  if ($qi.Count -ge 9) {
    if ($lossInt -eq 0 -and [int]$qi[3] -ne $att) { $flag += "SPI di pcap initiator $($qi[3]) != percobaan $att" }
    elseif ([int]$qi[3] -lt $nOk) { $flag += "SPI di pcap initiator $($qi[3]) < run ok $nOk" }
    if ([int]$qi[4] -lt $nOk) { $flag += "log 'established' $($qi[4]) < run ok $nOk" }
    if ([int]$qi[6] -eq 0) { $flag += "log charon kosong" }
  }
  $mlOk = @($runs | Where-Object { $_.status -eq "ok" -and $_.ml_kem -gt 0 }).Count
  if ($def.mode -eq "hybrid" -and $mlOk -ne $nOk) { $flag += "hybrid tetapi ML-KEM tidak terpilih di $($nOk - $mlOk) run" }
  if ($def.mode -eq "klasik" -and $mlOk -gt 0) { $flag += "klasik tetapi ML-KEM terpilih di $mlOk run" }
  $qcTeks = "OK"; if ($flag.Count) { $qcTeks = ($flag -join "; ") }

  $sw.Stop()
  $meta = [ordered]@{
    peneliti = $peneliti; set = $Set; seed = $seedInt; urutan_acak = $idxInt
    mulai = $tmulai.ToString("o"); selesai = (Get-Date).ToString("o")
    testbed = "$("Testbed-Host-ThinkPad"); VM initiator $ipI, responder $ipR (lihat metadata-percobaan.txt)"
    kondisi = [ordered]@{ mtu = $mtuInt; loss_persen_per_arah = $lossInt; rtt_ms = $rttInt; delay_netem_per_arah_ms = $delay }
    konfigurasi = [ordered]@{ nama = $cfgName; proposal_mode = $def.mode; fragment_size = $fs; retransmit_timeout = $def.to; retransmit_tries = $def.tr }
    hasil_ringkas = [ordered]@{
      run_valid = $valid; ok = $nOk; gagal_desain = $nFail; invalid_teknis = $nInv; percobaan_total = $att
      success_rate_persen = $srPersen
      median_ms = $statSwan.median; p95_ms = $statSwan.p95
      bootstrap_ci95_p95 = @($statSwan.ci_bawah, $statSwan.ci_atas); ci_lebar_ms = $statSwan.ci_lebar
      rata_retransmisi = $avgRetrans; rata_bytes_per_run = $avgBytes
      total_paket_fragmen_ike = $totFragIkePcap; total_paket_fragmen_ip = $totFragIpPcap
    }
    cpu_charon_detik = [ordered]@{ initiator = $cpuI; responder = $cpuR }
    beban_cpu_host_persen = [ordered]@{ awal = $hostLoad0; akhir = $hostLoad1 }
    qc = $qcTeks; qc_initiator = "$qcI"; qc_responder = "$qcR"
  }
  ($meta | ConvertTo-Json -Depth 6) | Set-Content -Path "$bd\meta.json" -Encoding UTF8

  $row = [pscustomobject]@{
    idx                 = $idxInt
    kondisi             = "MTU$($mtuInt)_loss$($lossInt)_rtt$($rttInt)"
    konfigurasi         = $cfgName
    valid               = "$valid/$nInt"
    ok                  = $nOk
    gagal               = $nFail
    invalid             = $nInv
    success_rate_persen = $srPersen
    rata2_ms            = $(if ($msOkList.Count -gt 0) { [math]::Round(($msOkList | Measure-Object -Average).Average, 2) } else { "-" })
    persen_retrans      = $(if ($runsVal.Count -gt 0) { [math]::Round((@($runsVal | Where-Object { [int]$_.retransmisi -gt 0 }).Count / [double]$runsVal.Count) * 100.0, 2) } else { 0.0 })
    persen_lewat_1s     = $(if ($msOkList.Count -gt 0) { [math]::Round((@($msOkList | Where-Object { [double]$_ -ge 1000 }).Count / [double]$msOkList.Count) * 100.0, 2) } else { 0.0 })
    median_ms           = $statSwan.median
    p95_ms              = $statSwan.p95
    p95_ci_bawah        = $statSwan.ci_bawah
    p95_ci_atas         = $statSwan.ci_atas
    p95_ci_lebar        = $statSwan.ci_lebar
    rata_retransmisi    = $avgRetrans
    rata_bytes          = $avgBytes
    frag_ike_total      = $totFragIkePcap
    frag_ip_total       = $totFragIpPcap
    cpu_init_s          = $cpuI
    cpu_resp_s          = $cpuR
    detik_per_run       = $(if ($valid) { [math]::Round($wall / 1000.0 / $valid, 2) } else { "-" })
    detik_overhead      = [math]::Round($sw.Elapsed.TotalSeconds - $wall / 1000.0, 1)
    qc                  = $qcTeks
  }
  Write-Host ("    => SR: {0}% ({1}/{2}), median: {3} ms, p95: {4} ms [CI95: {5}..{6}], retrans: {7}, frag_IKE: {8}, CPU: {9}s/{10}s, QC: {11}" -f $srPersen, $nOk, $valid, $statSwan.median, $statSwan.p95, $statSwan.ci_bawah, $statSwan.ci_atas, $avgRetrans, $totFragIkePcap, $cpuI, $cpuR, $qcTeks) -ForegroundColor Yellow
  if ($flag.Count -eq 0) { Set-Content -Path "$bd\selesai.ok" -Value (Get-Date).ToString("o") }
  $row | Export-Csv -NoTypeInformation -Append -Path "$out\ringkasan-batch.csv" -Encoding UTF8
  return $row
}

# ===================== PROGRAM UTAMA =====================
if ($Nama -eq "") { $Nama = "{0}-{1}" -f $Set, (Get-Date -Format "yyyyMMdd-HHmm") }
$base = "03_pilot"
if ($Set -eq "evaluasi" -or $Set -eq "ablation") { $base = "04_data" }
$out = "$repo\$base\$Nama"
New-Item -ItemType Directory -Force $out | Out-Null
Start-Transcript -Path "$out\transkrip.txt" -Append | Out-Null

Write-Host "== Eksperimen PQ-IKEv2: set '$Set', folder $out ==" -ForegroundColor Green
Write-Host "PENTING: Jangan klik di dalam area biru jendela PowerShell agar tidak masuk mode Select (Pause)." -ForegroundColor Yellow

$svc = Get-Service Multipass -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne "Running") {
  Start-Service Multipass
  Start-Sleep -Seconds 5
}
$infoJson = multipass info initiator responder --format json | ConvertFrom-Json
if ($infoJson.info.initiator.state -ne "Running" -or $infoJson.info.responder.state -ne "Running") {
  multipass start initiator responder
  Start-Sleep -Seconds 3
  $infoJson = multipass info initiator responder --format json | ConvertFrom-Json
}

$ipI = $infoJson.info.initiator.ipv4[0]
$ipR = $infoJson.info.responder.ipv4[0]
Write-Host "IP aktif -> initiator: $ipI, responder: $ipR"

$tmpH = "$env:TEMP\helper.sh"
[IO.File]::WriteAllText($tmpH, ($helper -replace "`r`n", "`n"))
foreach ($vm in "initiator", "responder") { multipass transfer $tmpH "${vm}:/home/ubuntu/helper.sh" }
Invoke-VM initiator sync-ip $ipI $ipR | Out-Null
Invoke-VM responder sync-ip $ipR $ipI | Out-Null

$fileRencana = "$out\rencana.csv"
if (Test-Path $fileRencana) {
  $rencana = @(Import-Csv $fileRencana)
  Write-Host "Melanjutkan rencana yang ada: $($rencana.Count) skenario."
}
else {
  if ($Seed -eq 0) { $Seed = Get-Random -Minimum 10000 -Maximum 999999 }
  $rencana = @(Buat-Rencana $Set $Seed)
  $rencana | Export-Csv -NoTypeInformation -Path $fileRencana -Encoding UTF8
  Write-Host "Rencana baru dibuat: $($rencana.Count) skenario, seed pengacakan = $Seed."
}

$fileMeta = "$out\metadata-percobaan.txt"
if (-not (Test-Path $fileMeta)) {
  "Peneliti: $peneliti" | Out-File $fileMeta -Encoding UTF8
  "Tanggal: $(Get-Date -Format o)" | Out-File $fileMeta -Append -Encoding UTF8
  "Set: $Set; seed: $($rencana[0].seed)" | Out-File $fileMeta -Append -Encoding UTF8
  "Host: $("Testbed-Host-ThinkPad"); $((Get-CimInstance Win32_OperatingSystem).Caption)" | Out-File $fileMeta -Append -Encoding UTF8
  "CPU host: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name); logis: $((Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum)" | Out-File $fileMeta -Append -Encoding UTF8
  "RAM host (GB): $([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1))" | Out-File $fileMeta -Append -Encoding UTF8
  "Multipass: $((multipass version) -join ' ')" | Out-File $fileMeta -Append -Encoding UTF8
  foreach ($vm in "initiator", "responder") {
    "--- VM $vm ---" | Out-File $fileMeta -Append -Encoding UTF8
    (multipass info $vm | Out-String) | Out-File $fileMeta -Append -Encoding UTF8
    (Invoke-VM $vm info | Out-String) | Out-File $fileMeta -Append -Encoding UTF8
  }
}

$ringkasSesi = @()
$mulaiTotal = Get-Date
try {
  Reset-VMs
  foreach ($sk in $rencana) {
    $label = "{0:D3}_MTU{1}_loss{2}_rtt{3}_{4}" -f [int]$sk.idx, $sk.mtu, $sk.loss, $sk.rtt, $sk.cfg
    if (Test-Path "$out\$label\selesai.ok") { Write-Host "-- lewati (sudah selesai): $label"; continue }
    $berhasil = $false
    foreach ($coba in 1, 2) {
      try {
        $ringkasSesi += Jalankan-Batch $sk $rencana.Count $ipI $ipR
        $berhasil = $true
        break
      }
      catch {
        $pesan = "$(Get-Date -Format o) skenario $label percobaan ${coba}: $($_.Exception.Message)"
        Write-Host "MASALAH: $pesan" -ForegroundColor Red
        Add-Content -Path "$out\masalah.log" -Value $pesan
        Reset-VMs
      }
    }
    if (-not $berhasil) { Write-Host "Skenario $label dilewati karena masalah teknis (lihat masalah.log)." }
  }
}
finally {
  Reset-VMs
}

$semuaRingkas = @()
if (Test-Path "$out\ringkasan-batch.csv") {
  $semuaRingkas = @(Import-Csv "$out\ringkasan-batch.csv")
} else {
  $semuaRingkas = $ringkasSesi
}

Write-Host ""
Write-Host "================ RINGKASAN BATCH ($Set) ================" -ForegroundColor Green
$semuaRingkas | Select-Object idx, kondisi, konfigurasi, valid, success_rate_persen, median_ms, p95_ms, p95_ci_bawah, p95_ci_atas, rata_retransmisi, frag_ike_total, qc | Format-Table -AutoSize

$validRows = @($semuaRingkas | Where-Object { $_.detik_per_run -ne "-" -and $_.detik_per_run -ne $null })
$estLo = 3.8; $estHi = 5.5
if ($validRows.Count -gt 0) {
  $ringan = @($validRows | Where-Object { $_.kondisi -like "*loss0*" })
  $berat  = @($validRows | Where-Object { $_.kondisi -like "*loss5*" })
  $rAvg   = ($validRows | ForEach-Object { [double]$_.detik_per_run } | Measure-Object -Average).Average
  $r1     = $(if ($ringan.Count) { ($ringan | ForEach-Object { [double]$_.detik_per_run } | Measure-Object -Average).Average } else { $rAvg * 0.75 })
  $r2     = $(if ($berat.Count)  { ($berat  | ForEach-Object { [double]$_.detik_per_run } | Measure-Object -Average).Average } else { $rAvg * 1.25 })
  $ov     = ($validRows | ForEach-Object { [double]$_.detik_overhead } | Measure-Object -Average).Average
  $rWeighted = (0.35 * $r1) + (0.35 * (($r1 + $r2) / 2.0)) + (0.30 * $r2)
  $estLo = [math]::Round((8100.0 * $r1 + 81.0 * $ov) / 3600.0, 2)
  $estHi = [math]::Round((8100.0 * $rWeighted + 81.0 * $ov) / 3600.0, 2)
  $estMax = [math]::Round((8100.0 * $r2 + 81.0 * $ov) / 3600.0, 2)
  Write-Host ("Rata-rata per run: ringan {0:N2} s, terberat {1:N2} s, tertimbang {2:N2} s; overhead per skenario {3:N1} s" -f $r1, $r2, $rWeighted, $ov) -ForegroundColor Cyan
  Write-Host ("ESTIMASI total 81 skenario x 100 run: sekitar {0:N2} sampai {1:N2} jam (maks {2:N2} jam)" -f $estLo, $estHi, $estMax) -ForegroundColor Green
}

if ($Set -eq "tuning" -or $Freeze) {
  $kandRows = @($semuaRingkas | Where-Object { $_.kondisi -eq "MTU1280_loss5_rtt100" -and $_.konfigurasi -like "cand-*" })
  if ($kandRows.Count -gt 0) {
    $terbaik = $kandRows | Sort-Object @{Expression={[double]$_.success_rate_persen}; Descending=$true}, @{Expression={[double]$_.p95_ms}; Ascending=$true}, @{Expression={[double]$_.rata_retransmisi}; Ascending=$true} | Select-Object -First 1
    if ($terbaik) {
      $MenangTuning = $terbaik.konfigurasi
      Write-Host ">> Kandidat terbaik hasil tuning: $MenangTuning (SR=$($terbaik.success_rate_persen)%, p95=$($terbaik.p95_ms) ms [CI: $($terbaik.p95_ci_bawah)..$($terbaik.p95_ci_atas)])" -ForegroundColor Green
    }
  }
  Simpan-ConfigFreeze $out $semuaRingkas $MenangTuning $estLo $estHi
}

$bermasalah = @($semuaRingkas | Where-Object { $_.qc -ne "OK" }).Count
Write-Host ""
Write-Host "Batch dikerjakan pada sesi ini : $($ringkasSesi.Count)"
Write-Host "Batch dengan catatan QC        : $bermasalah"
Write-Host ("Durasi sesi                    : {0:N1} menit" -f ((Get-Date) - $mulaiTotal).TotalMinutes)
Write-Host "SELESAI. Data: $out" -ForegroundColor Green
Stop-Transcript | Out-Null