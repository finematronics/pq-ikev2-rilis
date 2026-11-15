#!/usr/bin/env bash
# install.sh - testbed PQ-IKEv2 (Ubuntu 24.04): OpenSSL 3.5.0 + strongSwan 6.0.2 + tools
# Jalankan DI DALAM VM:  bash ~/install.sh 2>&1 | tee ~/install.log
set -euo pipefail

OPENSSL_VER=3.5.0
SWAN_VER=6.0.2
PREFIX_SSL=/opt/openssl-${OPENSSL_VER}
SRC=$HOME/src
mkdir -p "$SRC"

echo "=== [1/5] Paket dasar & alat ukur ==="
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential pkg-config perl curl ca-certificates bzip2 \
  libgmp-dev libsystemd-dev \
  tcpdump tshark sysstat iperf3 iproute2 mtr-tiny

echo "=== [2/5] OpenSSL ${OPENSSL_VER} (ke ${PREFIX_SSL}) ==="
cd "$SRC"
[ -f openssl-${OPENSSL_VER}.tar.gz ] || curl -fLO \
  https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz
tar xf openssl-${OPENSSL_VER}.tar.gz
cd openssl-${OPENSSL_VER}
./Configure --prefix=${PREFIX_SSL} --openssldir=${PREFIX_SSL}/ssl \
  --libdir=lib -Wl,-rpath,${PREFIX_SSL}/lib
make -j"$(nproc)"
sudo make install_sw install_ssldirs
${PREFIX_SSL}/bin/openssl version
${PREFIX_SSL}/bin/openssl list -kem-algorithms | grep -i ML-KEM-768 \
  || { echo "ML-KEM-768 TIDAK ditemukan"; exit 1; }

echo "=== [3/5] strongSwan ${SWAN_VER} ==="
cd "$SRC"
[ -f strongswan-${SWAN_VER}.tar.bz2 ] || curl -fLO \
  https://download.strongswan.org/strongswan-${SWAN_VER}.tar.bz2
tar xf strongswan-${SWAN_VER}.tar.bz2
cd strongswan-${SWAN_VER}
PKG_CONFIG_PATH=${PREFIX_SSL}/lib/pkgconfig \
CFLAGS="-I${PREFIX_SSL}/include" \
LDFLAGS="-L${PREFIX_SSL}/lib -Wl,-rpath,${PREFIX_SSL}/lib" \
./configure --prefix=/usr --sysconfdir=/etc \
  --enable-systemd --enable-swanctl --enable-vici --enable-openssl \
  --disable-stroke --disable-gmp
make -j"$(nproc)"
sudo make install

echo "=== [4/5] Layanan ==="
sudo systemctl daemon-reload
sudo systemctl enable --now strongswan.service || sudo systemctl enable --now strongswan-starter.service || true
sleep 3

echo "=== [5/5] Ringkasan versi ==="
uname -r
${PREFIX_SSL}/bin/openssl version
swanctl --version || true
tcpdump --version 2>&1 | head -1
tshark --version | head -1
pidstat -V 2>&1 | head -1
iperf3 --version | head -1
tc -V
systemctl is-active strongswan || true
sudo swanctl --list-algs 2>/dev/null | grep -i -E 'ml_kem|mlkem' || echo "(cek ML-KEM di --list-algs setelah daemon aktif)"
echo "SELESAI. Log: ~/install.log"
