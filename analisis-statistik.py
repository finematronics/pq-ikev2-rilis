#!/usr/bin/env python3
# analisis-statistik.py - Analisis statistik Tabel 3.10 Proposal pada data evaluasi terkunci.
# HANYA MEMBACA EVALUASI-semua-8900-runs.csv. Keluaran ke folder 05_analisis (STAT-*.csv, STAT-RINGKASAN.md).
# Pemakaian: python analisis-statistik.py <jalur EVALUASI-semua-8900-runs.csv> <folder keluaran>
# Perlu: numpy, pandas, scipy.  Seed bootstrap tetap: 11680.
import sys, os, itertools
import numpy as np, pandas as pd
from scipy import stats

SEED = 11680
B = 10000
KRITIS = [(1280, 5, 10), (1280, 5, 50), (1280, 5, 100)]   # MTU, loss, RTT: kondisi kritis proposal (MTU 1280; loss 5%)
ABL = [(1280, 0, 50), (1280, 5, 50), (1500, 0, 50), (1500, 5, 50)]


def holm(p):
    p = np.asarray(p, float); m = len(p); o = np.argsort(p); adj = np.empty(m); run = 0.0
    for i, k in enumerate(o):
        run = max(run, (m - i) * p[k]); adj[k] = min(1.0, run)
    return adj


def cliff(a, b):  # P(a>b) - P(a<b); negatif = a cenderung lebih kecil
    u = stats.mannwhitneyu(a, b, alternative='two-sided').statistic
    return 2.0 * u / (len(a) * len(b)) - 1.0


def cohen_h(p1, p2):
    return 2 * np.arcsin(np.sqrt(p1)) - 2 * np.arcsin(np.sqrt(p2))


def boot_diff(a, b, rng, B=B):
    a = np.asarray(a, float); b = np.asarray(b, float)
    ia = rng.integers(0, len(a), (B, len(a))); ib = rng.integers(0, len(b), (B, len(b)))
    d = a[ia].mean(1) - b[ib].mean(1)
    return a.mean() - b.mean(), np.percentile(d, 2.5), np.percentile(d, 97.5)


def sel(df, cfg, mtu=None, loss=None, rtt=None):
    m = df.konfigurasi == cfg
    if mtu is not None: m &= df.mtu_byte == mtu
    if loss is not None: m &= df.loss_persen == loss
    if rtt is not None: m &= df.rtt_ms == rtt
    return df[m]


def art_anova(d):
    """ART + ANOVA seimbang 3x3x3 (MTU x loss x RTT) pada ms_total_swanctl satu konfigurasi."""
    mt = sorted(d.mtu_byte.unique()); ls = sorted(d.loss_persen.unique()); rt = sorted(d.rtt_ms.unique())
    a = d.mtu_byte.map({v: i for i, v in enumerate(mt)}).values
    b = d.loss_persen.map({v: i for i, v in enumerate(ls)}).values
    c = d.rtt_ms.map({v: i for i, v in enumerate(rt)}).values
    y = d.ms_total_swanctl.values.astype(float); n = len(y) // 27

    def cellmeans(v):
        m = np.zeros((3, 3, 3))
        for i, j, k in itertools.product(range(3), repeat=3):
            m[i, j, k] = v[(a == i) & (b == j) & (c == k)].mean()
        return m

    def effects(m):
        G = m.mean(); mA = m.mean((1, 2)); mB = m.mean((0, 2)); mC = m.mean((0, 1))
        mAB = m.mean(2); mAC = m.mean(1); mBC = m.mean(0)
        e = {'MTU': mA[:, None, None] - G + 0 * m, 'loss': mB[None, :, None] - G + 0 * m, 'RTT': mC[None, None, :] - G + 0 * m,
             'MTU:loss': mAB[:, :, None] - mA[:, None, None] - mB[None, :, None] + G + 0 * m,
             'MTU:RTT': mAC[:, None, :] - mA[:, None, None] - mC[None, None, :] + G + 0 * m,
             'loss:RTT': mBC[None, :, :] - mB[None, :, None] - mC[None, None, :] + G + 0 * m}
        e['MTU:loss:RTT'] = m - mAB[:, :, None] - mAC[:, None, :] - mBC[None, :, :] + mA[:, None, None] + mB[None, :, None] + mC[None, None, :] - G
        return e

    cm = cellmeans(y); ef = effects(cm); res = y - cm[a, b, c]
    dfs = {'MTU': 2, 'loss': 2, 'RTT': 2, 'MTU:loss': 4, 'MTU:RTT': 4, 'loss:RTT': 4, 'MTU:loss:RTT': 8}
    rows = []
    for name, e in ef.items():
        al = res + e[a, b, c]; r = stats.rankdata(al)
        rm = cellmeans(r); er = effects(rm)[name]
        ss = n * np.sum(er ** 2); sse = np.sum((r - rm[a, b, c]) ** 2); dfe = len(y) - 27
        F = (ss / dfs[name]) / (sse / dfe)
        rows.append(dict(efek=name, df=dfs[name], df_galat=dfe, F=F, p=stats.f.sf(F, dfs[name], dfe)))
    return pd.DataFrame(rows)


def dunn(groups, labels):
    allv = np.concatenate(groups); N = len(allv); r = stats.rankdata(allv)
    _, t = np.unique(allv, return_counts=True); tie = np.sum(t ** 3 - t) / (12.0 * (N - 1))
    s2 = N * (N + 1) / 12.0 - tie
    idx = np.cumsum([0] + [len(g) for g in groups]); mr = [r[idx[i]:idx[i + 1]].mean() for i in range(len(groups))]
    out = []
    for i, j in itertools.combinations(range(len(groups)), 2):
        z = (mr[i] - mr[j]) / np.sqrt(s2 * (1 / len(groups[i]) + 1 / len(groups[j])))
        out.append((labels[i], labels[j], z, 2 * stats.norm.sf(abs(z))))
    adj = holm([o[3] for o in out])
    return [dict(level_a=o[0], level_b=o[1], z=o[2], p=o[3], p_holm=ad) for o, ad in zip(out, adj)]


def main():
    src, outd = sys.argv[1], sys.argv[2]
    os.makedirs(outd, exist_ok=True); rng = np.random.default_rng(SEED)
    df = pd.read_csv(src, encoding='utf-8-sig')
    assert len(df) == 8900 and (df.status == 'ok').all()
    L = []

    # --- RQ1: pengaruh faktor ---
    art_rows, kw_rows, dn_rows = [], [], []
    for cfg in ['klasik', 'hybrid-default', 'hybrid-optimized']:
        d = df[df.konfigurasi == cfg]
        t = art_anova(d); t.insert(0, 'konfigurasi', cfg); art_rows.append(t)
        for fac, col in [('MTU', 'mtu_byte'), ('loss', 'loss_persen'), ('RTT', 'rtt_ms')]:
            lv = sorted(d[col].unique()); gs = [d[d[col] == v].ms_total_swanctl.values for v in lv]
            H, p = stats.kruskal(*gs); kw_rows.append(dict(konfigurasi=cfg, faktor=fac, H=H, p=p, n=len(d)))
            for r in dunn(gs, lv): r.update(konfigurasi=cfg, faktor=fac); dn_rows.append(r)
    pd.concat(art_rows).to_csv(f'{outd}/STAT-RQ1-ART-ANOVA.csv', index=False)
    pd.DataFrame(kw_rows).to_csv(f'{outd}/STAT-RQ1-KruskalWallis.csv', index=False)
    pd.DataFrame(dn_rows).to_csv(f'{outd}/STAT-RQ1-Dunn-Holm.csv', index=False)

    # --- RQ2/RQ3 terencana: kondisi kritis (MTU 1280; loss 5%) ---
    def uji(cfa, cfb, cells, alt, fam):
        rows = []
        for (m, l, r) in cells:
            a = sel(df, cfa, m, l, r).ms_total_swanctl.values; b = sel(df, cfb, m, l, r).ms_total_swanctl.values
            u = stats.mannwhitneyu(a, b, alternative=alt)
            sa = (sel(df, cfa, m, l, r).status == 'ok').sum(); sb = (sel(df, cfb, m, l, r).status == 'ok').sum()
            fa = 'greater' if alt == 'less' else 'two-sided'
            pf = stats.fisher_exact([[sa, len(a) - sa], [sb, len(b) - sb]], alternative=fa)[1]
            rows.append(dict(keluarga=fam, A=cfa, B=cfb, MTU=m, loss=l, RTT=r, nA=len(a), nB=len(b), arah=alt,
                             rata2_A=a.mean(), rata2_B=b.mean(), median_A=np.median(a), median_B=np.median(b),
                             retx_A_persen=100 * (sel(df, cfa, m, l, r).retransmisi > 0).mean(),
                             retx_B_persen=100 * (sel(df, cfb, m, l, r).retransmisi > 0).mean(),
                             MWU_p=u.pvalue, cliff_delta_A_vs_B=cliff(a, b),
                             sukses_A=f'{sa}/{len(a)}', sukses_B=f'{sb}/{len(b)}', Fisher_p=pf,
                             cohen_h=cohen_h(sa / len(a), sb / len(b))))
        t = pd.DataFrame(rows); t['MWU_p_Holm'] = holm(t.MWU_p); return t
    plan = pd.concat([uji('hybrid-optimized', 'hybrid-default', KRITIS, 'less', 'H1(2)/H1(1): optimized vs default'),
                      uji('klasik', 'hybrid-default', KRITIS, 'two-sided', 'H0(3): klasik vs hybrid-default'),
                      uji('klasik', 'hybrid-optimized', KRITIS, 'two-sided', 'H0(3): klasik vs hybrid-optimized')])
    plan.to_csv(f'{outd}/STAT-RQ2-terencana-kondisi-kritis.csv', index=False)

    # --- Eksploratori: semua 27 kondisi (tanpa klaim konfirmatori) ---
    allc = [(m, l, r) for m in (1280, 1400, 1500) for l in (0, 1, 5) for r in (10, 50, 100)]
    ex = pd.concat([uji('hybrid-optimized', 'hybrid-default', allc, 'less', 'EKSPLORATORI optimized vs default'),
                    uji('klasik', 'hybrid-default', allc, 'two-sided', 'EKSPLORATORI klasik vs hybrid-default'),
                    uji('klasik', 'hybrid-optimized', allc, 'two-sided', 'EKSPLORATORI klasik vs hybrid-optimized')])
    ex.to_csv(f'{outd}/STAT-eksploratori-27-kondisi.csv', index=False)

    # --- Eksploratori: selisih rata-rata + CI bootstrap (kondisi kritis, gabungan loss) ---
    rows = []
    def add(lbl, cfa, cfb, fa, fb):
        a = df[fa(df) & (df.konfigurasi == cfa)].ms_total_swanctl.values; b = df[fb(df) & (df.konfigurasi == cfb)].ms_total_swanctl.values
        d, lo, hi = boot_diff(a, b, rng); rows.append(dict(kontras=lbl, A=cfa, B=cfb, nA=len(a), nB=len(b), selisih_rata2_ms=d, ci95_bawah=lo, ci95_atas=hi, cliff_delta=cliff(a, b)))
    for (m, l, r) in KRITIS:
        f = (lambda d, m=m, l=l, r=r: (d.mtu_byte == m) & (d.loss_persen == l) & (d.rtt_ms == r))
        add(f'MTU{m} loss{l} RTT{r}', 'hybrid-optimized', 'hybrid-default', f, f)
        add(f'MTU{m} loss{l} RTT{r}', 'hybrid-optimized', 'klasik', f, f)
        add(f'MTU{m} loss{l} RTT{r}', 'hybrid-default', 'klasik', f, f)
    for l in (1, 5):
        f = (lambda d, l=l: d.loss_persen == l)
        add(f'loss{l} semua MTU/RTT', 'hybrid-optimized', 'hybrid-default', f, f)
        add(f'loss{l} semua MTU/RTT', 'hybrid-optimized', 'klasik', f, f)
        add(f'loss{l} semua MTU/RTT', 'hybrid-default', 'klasik', f, f)
    pd.DataFrame(rows).to_csv(f'{outd}/STAT-eksploratori-selisih-rata2-bootstrap.csv', index=False)

    # --- RQ3: ablasi (default, +A, +B, optimized) pada 4 sel proposal ---
    rows = []
    for (m, l, r) in ABL:
        g = {c: sel(df, c, m, l, r).ms_total_swanctl.values for c in ['hybrid-default', 'hybrid-plusA', 'hybrid-plusB', 'hybrid-optimized']}
        for ca, cb in [('hybrid-plusA', 'hybrid-default'), ('hybrid-plusB', 'hybrid-default'), ('hybrid-optimized', 'hybrid-default'), ('hybrid-optimized', 'hybrid-plusB'), ('hybrid-optimized', 'hybrid-plusA')]:
            d, lo, hi = boot_diff(g[ca], g[cb], rng)
            rows.append(dict(MTU=m, loss=l, RTT=r, A=ca, B=cb, nA=len(g[ca]), nB=len(g[cb]), selisih_rata2_ms=d, ci95_bawah=lo, ci95_atas=hi,
                             MWU_p_2arah=stats.mannwhitneyu(g[ca], g[cb]).pvalue, cliff_delta=cliff(g[ca], g[cb])))
    pd.DataFrame(rows).to_csv(f'{outd}/STAT-RQ3-ablasi.csv', index=False)

    # --- Ringkasan teks ---
    art = pd.concat(art_rows)
    with open(f'{outd}/STAT-RINGKASAN.txt', 'w', encoding='utf-8', newline='\n') as f:
        f.write('RINGKASAN ANALISIS STATISTIK (otomatis)\n')
        f.write('Sumber: %s (8.900 run). Seed bootstrap %d, B = %d.\n\n' % (os.path.basename(src), SEED, B))
        f.write('RQ1 - ART-ANOVA per konfigurasi\n' + art.to_string(index=False, float_format=lambda x: '%.4g' % x) + '\n\n')
        f.write('RQ1 - Kruskal-Wallis per faktor\n' + pd.DataFrame(kw_rows).to_string(index=False, float_format=lambda x: '%.4g' % x) + '\n\n')
        f.write('Perbandingan terencana, kondisi kritis (MTU 1280; loss 5%)\n' + plan.to_string(index=False, float_format=lambda x: '%.4g' % x) + '\n\n')
        f.write('Berkas lain: STAT-RQ1-Dunn-Holm.csv, STAT-RQ3-ablasi.csv, STAT-eksploratori-*.csv\n')
    print('selesai ->', outd)


if __name__ == '__main__':
    main()
