# Catatan Pemeliharaan Proyek

Saat menambah fitur atau mengubah perilaku aplikasi:

- Sertakan catatan pemeliharaan yang jelas dan berdekatan dengan perubahan. Jelaskan tujuan fungsi/alur, data atau state yang dibaca/diubah, batasan mockup, dan bagian yang harus disesuaikan saat perilaku berubah atau backend tersedia.
- Hindari catatan umum seperti "hubungkan ke API" tanpa menyebut tindakan backend yang dibutuhkan (misalnya validasi kredensial, penyimpanan hash, atau pemuatan data). Jangan mengulang arti nama fungsi; jelaskan aturan atau alasan yang tidak terlihat langsung dari kode.
- Untuk perilaku yang belum terhubung ke backend, tampilkan penanda mockup di UI dan beri komentar `CATATAN MOCKUP` pada titik logika terkait.
- Perbarui `README.md` jika perubahan memengaruhi cara menjalankan aplikasi, arsitektur, atau alur pengembangan.
- Catatan harus membantu orang memahami atau melanjutkan perubahan; hindari komentar yang hanya mengulang arti kode yang sudah jelas.
- Setelah perubahan, jalankan pemeriksaan dan tes yang relevan, lalu laporkan hasilnya.
