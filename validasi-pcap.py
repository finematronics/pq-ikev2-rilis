#!/usr/bin/env python3
# validasi-pcap.py - Validasi struktural initiator.pcap terhadap runs.csv (Tahap 6).
# HANYA MEMBACA data eksperimen. Hasil ditulis ke 05_analisis. Hanya pustaka standar Python.
# Pemakaian:  python validasi-pcap.py            (semua 89 batch)
#             python validasi-pcap.py 8 20       (hanya batch bernomor 8 dan 20)
import csv, os, re, subprocess, sys, statistics
from collections import Counter

REPO = os.path.join(os.environ.get('USERPROFILE', os.path.expanduser('~')), 'Documents', 'pq-ikev2')
DATA = os.path.join(REPO, '04_data', 'evaluasi-20261114-1749')
OUTD = os.path.join(REPO, '05_analisis')
CACHE = os.path.join(OUTD, 'cache-tshark')
VM = 'initiator'
RE_BATCH = re.compile(r'^(\d{3})_MTU(\d+)_loss(\d+)_rtt(\d+)_(.+)$')
RE_MID = re.compile(r'MID=(\d+)')
RESIDU_NORMAL = (8.0, 16.0)   # ms, rentang residu run normal
RESIDU_JITTER_MAX = 60.0      # ms, di atas normal tapi masih jitter
TOL_HIDDEN = 50.0             # ms, toleransi lompatan residu = kelipatan timeout
NORMAL_MED = 12.0             # ms, median residu normal (hasil sampel 4 batch)
BACKOFF = 1.8
FIELDS = ['frame.number', 'frame.time_epoch', 'ip.src', 'frame.len', 'isakmp.exchangetype', '_ws.col.info']


def baca_csv(path):
    with open(path, newline='', encoding='utf-8-sig') as f:
        head = f.readline(); f.seek(0)
        delim = ';' if head.count(';') > head.count(',') else ','
        return list(csv.DictReader(f, delimiter=delim))


def jalankan(args):
    r = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        raise RuntimeError('Gagal: %s\n%s' % (' '.join(args), r.stderr))
    return r.stdout


def ekstrak_tshark(pcap, nomor):
    cache = os.path.join(CACHE, '%s.tsv' % nomor)
    if os.path.exists(cache) and os.path.getsize(cache) > 0:
        with open(cache, encoding='utf-8') as f:
            return f.read()
    remote = '/tmp/vp_%s.pcap' % nomor
    jalankan(['multipass', 'transfer', pcap, '%s:%s' % (VM, remote)])
    cmd = 'tshark -r %s -Y isakmp -T fields %s -E separator=/t' % (remote, ' '.join('-e ' + x for x in FIELDS))
    out = jalankan(['multipass', 'exec', VM, '--', 'bash', '-c', cmd])
    jalankan(['multipass', 'exec', VM, '--', 'rm', '-f', remote])
    os.makedirs(CACHE, exist_ok=True)
    with open(cache, 'w', encoding='utf-8', newline='\n') as f:
        f.write(out)
    return out


def parse_tsv(text):
    pk = []
    for line in text.splitlines():
        p = line.split('\t')
        if len(p) < 6:
            continue
        try:
            no = int(p[0]); t = float(p[1]); ln = int(p[3])
        except ValueError:
            continue
        ex = p[4].split(',')[0].strip()
        ex = int(ex) if ex else -1
        m = RE_MID.search(p[5])
        pk.append(dict(no=no, t=t, src=p[2], len=ln, ex=ex, info=p[5],
                       mid=int(m.group(1)) if m else -1,
                       req='Request' in p[5], frag='(fragment' in p[5]))
    return pk


def kelipatan_kumulatif(T):
    s, out = 0.0, []
    for k in range(4):
        s += T * BACKOFF ** k
        out.append(s * 1000.0)
    return out


def analisis_run(pk, run, ip_ini):
    T = float(run['retransmit_timeout_s']); rtt = float(run['rtt_ms'])
    ms = float(run['ms_total_swanctl']); log = int(float(run['retransmisi']))
    hs = sorted([x for x in pk if x['ex'] != 37 and 0 <= x['mid'] <= 2], key=lambda x: x['t'])
    resp = [x for x in hs if x['ex'] == 35 and not x['req'] and x['src'] != ip_ini]
    pcap_ms = residu = None
    if hs and resp:
        pcap_ms = (resp[0]['t'] - hs[0]['t']) * 1000.0
        residu = ms - (pcap_ms + rtt / 2.0)
        upto = [x['t'] for x in hs if x['t'] <= resp[0]['t']]
    else:
        upto = [x['t'] for x in hs]
    cnt = Counter((x['mid'], x['info']) for x in hs if x['req'] and x['src'] == ip_ini)
    dup_n = sum(c - 1 for c in cnt.values())
    gap_n = sum(1 for a, b in zip(upto, upto[1:]) if (b - a) * 1000.0 >= 0.8 * T * 1000.0)
    pcap_flag = dup_n > 0 or gap_n > 0
    kelas = 'TANPA_AUTH_RESP'
    k_hid = 0
    if residu is not None:
        if RESIDU_NORMAL[0] <= residu <= RESIDU_NORMAL[1]:
            kelas = 'normal'
        else:
            kelas = 'ANOMALI'
            for k, s in enumerate(kelipatan_kumulatif(T), 1):
                if abs(residu - NORMAL_MED - s) <= TOL_HIDDEN:
                    kelas = 'init_tersembunyi_x%d' % k; k_hid = k
                    break
            else:
                if RESIDU_NORMAL[1] < residu <= RESIDU_JITTER_MAX:
                    kelas = 'jitter'
    if (log > 0) == pcap_flag:
        cocok = 'cocok'
    elif log > 0 and not pcap_flag and k_hid > 0:
        cocok = 'wajar_init_tersembunyi'
    else:
        cocok = 'TAK_TERJELASKAN'
    if k_hid and log < k_hid:
        cocok = 'TAK_TERJELASKAN'
    n_pkt = len(pk)
    return dict(percobaan=run['percobaan'], rtt_ms=rtt, ms_swanctl=ms, retransmisi_log=log,
                ms_pcap=None if pcap_ms is None else round(pcap_ms, 2),
                residu_ms=None if residu is None else round(residu, 2), kelas_residu=kelas,
                n_paket=n_pkt, n_fragmen=sum(1 for x in pk if x['frag']),
                bytes=sum(x['len'] for x in pk if x['ex'] != 37),
                dup_paket=dup_n, jeda_ge_08timeout=gap_n, retx_terlihat_pcap=pcap_flag, status=cocok)


def proses_batch(info, pk_all, runs, ring):
    ip_ini = runs[0].get('ip_initiator', '10.97.0.149')
    wins = sorted(((int(r['mulai_epoch_ns']) / 1e9, int(r['selesai_epoch_ns']) / 1e9, r) for r in runs), key=lambda w: w[0])
    per_run, dipakai = [], set()
    for (a, b, r) in wins:
        pk = [x for x in pk_all if a <= x['t'] <= b]
        for x in pk:
            dipakai.add(x['no'])
        d = analisis_run(pk, r, ip_ini)
        d.update(batch=info['nomor'], konfigurasi=info['cfg'], mtu=info['mtu'], loss=info['loss'])
        per_run.append(d)
    orphan = [x for x in pk_all if x['no'] not in dipakai and x['ex'] != 37]
    bytes_all = sum(x['len'] for x in pk_all if x['ex'] != 37)
    frag_all = sum(1 for x in pk_all if x['frag'])
    n = len(runs)
    rb_ring = float(ring['rata_bytes']) if ring else None
    fg_ring = int(float(ring['frag_ike_total'])) if ring else None
    kelas = Counter(d['kelas_residu'] for d in per_run)
    normal = [d['residu_ms'] for d in per_run if d['kelas_residu'] == 'normal']
    batch = dict(batch=info['nomor'], folder=info['folder'], konfigurasi=info['cfg'], loss=info['loss'], rtt=info['rtt'],
                 runs=n, orphan_paket=len(orphan),
                 rata_bytes_pcap=round(bytes_all / n, 2), rata_bytes_ringkasan=rb_ring,
                 frag_pcap=frag_all, frag_ringkasan=fg_ring,
                 run_retx_log=sum(1 for d in per_run if d['retransmisi_log'] > 0),
                 run_retx_pcap=sum(1 for d in per_run if d['retx_terlihat_pcap']),
                 run_init_tersembunyi=sum(v for k, v in kelas.items() if k.startswith('init_tersembunyi')),
                 run_anomali=kelas.get('ANOMALI', 0) + kelas.get('TANPA_AUTH_RESP', 0),
                 run_jitter=kelas.get('jitter', 0),
                 run_tak_terjelaskan=sum(1 for d in per_run if d['status'] == 'TAK_TERJELASKAN'),
                 residu_median_normal=round(statistics.median(normal), 2) if normal else None,
                 persen_normal=round(100.0 * len(normal) / n, 1))
    return per_run, batch


def tulis_csv(path, rows):
    if not rows:
        return
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)


def laporan(all_runs, batches):
    L = []
    L.append('VALIDASI STRUKTURAL PCAP vs runs.csv - %d batch, %d run' % (len(batches), len(all_runs)))
    gagal = []
    for b in batches:
        if b['orphan_paket'] != 0:
            gagal.append('batch %s: %d paket handshake di luar semua jendela run' % (b['batch'], b['orphan_paket']))
        if b['rata_bytes_ringkasan'] is not None and abs(b['rata_bytes_pcap'] - b['rata_bytes_ringkasan']) > 0.51:
            gagal.append('batch %s: rata_bytes pcap %.2f != ringkasan %.2f' % (b['batch'], b['rata_bytes_pcap'], b['rata_bytes_ringkasan']))
        if b['frag_ringkasan'] is not None and b['frag_pcap'] != b['frag_ringkasan']:
            gagal.append('batch %s: frag pcap %d != ringkasan %d' % (b['batch'], b['frag_pcap'], b['frag_ringkasan']))
        if b['run_tak_terjelaskan'] or b['run_anomali']:
            gagal.append('batch %s: %d run tak terjelaskan, %d run anomali' % (b['batch'], b['run_tak_terjelaskan'], b['run_anomali']))
    kelas = Counter(d['kelas_residu'] for d in all_runs)
    L.append('Kelas residu: ' + ', '.join('%s=%d' % kv for kv in sorted(kelas.items())))
    L.append('Status log-vs-pcap: ' + ', '.join('%s=%d' % kv for kv in sorted(Counter(d['status'] for d in all_runs).items())))
    for lbl, flt in (('loss 0%', lambda d: d['loss'] == '0'), ('loss >0%', lambda d: d['loss'] != '0')):
        x = [d['residu_ms'] for d in all_runs if flt(d) and d['kelas_residu'] == 'normal']
        if x:
            L.append('Residu normal %s: n=%d min=%.1f median=%.1f max=%.1f ms' % (lbl, len(x), min(x), statistics.median(x), max(x)))
    l0 = [d for d in all_runs if d['loss'] == '0']
    if l0:
        out = [d for d in l0 if d['kelas_residu'] != 'normal']
        L.append('Run loss 0%% dengan residu di luar %.0f-%.0f ms: %d dari %d (jitter=%d, anomali=%d)' % (RESIDU_NORMAL[0], RESIDU_NORMAL[1], len(out), len(l0), sum(1 for d in out if d['kelas_residu'] == 'jitter'), sum(1 for d in out if d['kelas_residu'] in ('ANOMALI', 'TANPA_AUTH_RESP'))))
    L.append('Run tersembunyi (paket pertama IKE_SA_INIT jatuh di egress): %d' % sum(v for k, v in kelas.items() if k.startswith('init_tersembunyi')))
    L.append('')
    L.append('PEMERIKSAAN GAGAL: %d' % len(gagal))
    L.extend(' - ' + g for g in gagal)
    L.append('HASIL: ' + ('LULUS' if not gagal else 'ADA TEMUAN - periksa daftar di atas'))
    return '\n'.join(L)


def main():
    pilih = set(int(a) for a in sys.argv[1:])
    ring_all = {int(float(r['idx'])): r for r in baca_csv(os.path.join(DATA, 'ringkasan-batch.csv'))}
    folders = sorted(d for d in os.listdir(DATA) if RE_BATCH.match(d) and os.path.isdir(os.path.join(DATA, d)))
    all_runs, batches = [], []
    for d in folders:
        m = RE_BATCH.match(d); nomor = int(m.group(1))
        if pilih and nomor not in pilih:
            continue
        info = dict(nomor=nomor, folder=d, mtu=m.group(2), loss=m.group(3), rtt=m.group(4), cfg=m.group(5))
        runs = baca_csv(os.path.join(DATA, d, 'runs.csv'))
        print('[%02d] %s ...' % (nomor, d), flush=True)
        pk = parse_tsv(ekstrak_tshark(os.path.join(DATA, d, 'initiator.pcap'), '%03d' % nomor))
        pr, b = proses_batch(info, pk, runs, ring_all.get(nomor))
        all_runs.extend(pr); batches.append(b)
    os.makedirs(OUTD, exist_ok=True)
    sufiks = '' if not pilih else '-sebagian'
    tulis_csv(os.path.join(OUTD, 'VALIDASI-pcap-per-run%s.csv' % sufiks), all_runs)
    tulis_csv(os.path.join(OUTD, 'VALIDASI-pcap-per-batch%s.csv' % sufiks), batches)
    txt = laporan(all_runs, batches)
    with open(os.path.join(OUTD, 'VALIDASI-pcap-ringkasan%s.txt' % sufiks), 'w', encoding='utf-8') as f:
        f.write(txt + '\n')
    print(); print(txt)


if __name__ == '__main__':
    main()
