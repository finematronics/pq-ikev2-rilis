# Catatan sanitasi salinan rilis

Salinan ini dibuat dari `git archive HEAD` repositori privat (tanpa riwayat commit).

Diubah:
- Nama mesin peneliti diganti `<HOST_PENELITI>` pada `01_pengukuran/mtr_*.txt`.
- Jalur akun `C:\Users\<akun_asli>` dan `<HOST_PENELITI>\<akun_asli>` diganti `C:\Users\<USER>` dan `<HOST_PENELITI>\<USER>` pada `02_testbed/bukti/bukti-tahap2.txt` dan `03_pilot/arsip-pilot-awal/pilot*.txt`.
- Kunci pra-bagi (PSK) pada konfigurasi telah diganti `<PSK_LAB_DIGANTI>` sejak sebelum rilis.

Tidak diubah:
- Seluruh data eksperimen utama (`04_data/evaluasi-20261114-1749/`), `jalankan-eksperimen.ps1`, dan skrip analisis. Hash terkunci tetap sama dengan repositori privat.
- Angka `2407187` pada `jalankan-eksperimen.ps1` adalah seed PRNG bootstrap CI (bukan seed pengacakan skenario, yaitu `11680`). Mengubahnya akan mengubah hasil CI dan hash skrip.
Tambahan:
- Nama mesin peneliti (`<HOST_PENELITI>`) dan jalur akun (`<USER>`) juga diganti pada 34 `meta.json` (`03_pilot/` dan `04_data/ablation-20261114-1428/`) serta 2 `CONFIG_FREEZE_SNAPSHOT.md`. Folder evaluasi utama tidak diubah.