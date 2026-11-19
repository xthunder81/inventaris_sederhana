# Inventaris Sederhana

Aplikasi inventaris sekolah dengan klien Flutter dan API Go. Pengembangan lokal menggunakan MongoDB Laragon di `localhost:27017`.

## Menjalankan website Flutter

Website Flutter responsif tersedia untuk Web, Windows, dan Android. Login, ganti kata sandi akun aktif, daftar/tambah/ubah/arsip pengguna, CRUD lokasi/jenis/kategori, daftar dan pencatatan aset individual, mutasi stok, serta laporan pemeliharaan memakai API Go dan MongoDB. Grafik tren dashboard dan pratinjau laporan masih belum terhubung penuh. Reset kata sandi pengguna oleh admin juga masih pratinjau dan tidak mengubah akun.

```powershell
# Terminal API: jalankan dari folder backend setelah menyetel rahasia dan URI.
cd backend
$bytes = New-Object byte[] 48
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$env:JWT_SECRET = [Convert]::ToBase64String($bytes)
$env:MONGODB_URI = "mongodb://127.0.0.1:27017"
$env:MONGODB_DATABASE = "inventaris_sederhana"
$env:HTTP_ADDR = "127.0.0.1:8081"
$env:CORS_ALLOWED_ORIGINS = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:5173,http://127.0.0.1:5173"
# Jalankan satu kali setelah database diinisialisasi untuk membuat admin.
go run ./cmd/bootstrap-admin
go run ./cmd/server
```

Di terminal lain, jalankan klien Web. Origin ini harus sama dengan allowlist API:

```powershell
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8081
```

Port 8080 adalah port web lokal yang umum dipakai Flutter; API memakai port 8081 agar keduanya tidak bertabrakan. Origin web di atas harus sama persis dengan `CORS_ALLOWED_ORIGINS` pada proses API. Jalankan backend sebelum membuka website dan siapkan admin memakai `go run ./cmd/bootstrap-admin`. Di browser, token sesi disimpan dalam `sessionStorage` agar reload pada tab yang sama tidak mengeluarkan pengguna; sesi tetap berakhir sesuai token API setelah 15 menit dan ditutup saat tab ditutup. Penyimpanan browser dapat dibaca JavaScript, jadi deployment yang lebih ketat sebaiknya menggunakan cookie `HttpOnly` melalui backend. Pada aplikasi Windows/Android, token masih berada di memori proses dan tidak dipulihkan setelah aplikasi ditutup. Untuk akses dari perangkat lain, ganti `127.0.0.1` pada `API_BASE_URL` dengan alamat server, set `HTTP_ADDR=0.0.0.0:8081`, dan atur CORS ke origin website yang tepat.

Halaman inventaris (pencarian, filter, detail, perubahan kondisi, dan riwayat) membaca data aset dari API. Setiap penyimpanan membuat satu unit dengan barcode server; pencatatan saldo stok massal tidak termasuk. Metrik ringkasan kondisi dashboard ikut memakai daftar aset aktual, tetapi grafik tren masih pratinjau. Mutasi stok dan laporan pemeliharaan disimpan server-side; pratinjau ekspor PDF/CSV belum menghasilkan file. Cetak label menghasilkan PDF satu halaman ukuran 80 × 42 mm dan membuka dialog cetak Web/Windows/Android. Atur driver printer ke media label yang sesuai, atau pilih skala aktual tanpa fit-to-page agar barcode tidak berubah ukuran.

Lokasi dan kategori barang pada dialog tambah aset dipilih dari master aktif; ID referensi dikirim ke server, bukan nama yang diketik bebas. Aset menyimpan `location_id` dan `condition_id`; item induk disimpan di `items` dan unit/barcode di `assets`. Item induk digunakan kembali bila nama, jenis `tidak_habis_pakai`, dan kategori sama persis, sedangkan setiap simpanan membuat unit aset baru. Jika pembuatan unit gagal setelah item induk baru tersimpan, item induk tetap valid sebagai katalog karena instalasi MongoDB standalone tidak mendukung transaksi lintas dokumen. API menampilkan loading/error/retry dan tidak mengganti kegagalan dengan data demo.

Komponen shell yang digunakan ulang tersedia di `lib/shared/widgets/`:

- `app_header.dart` untuk header, pencarian, notifikasi, dan profil.
- `app_navbar.dart` untuk navigasi samping.
- `app_footer.dart` untuk identitas sekolah di bagian bawah navigasi.

Halaman cukup memakai widget bersama tersebut dan memberikan callback/data yang diperlukan, bukan menyalin markup navbar atau footer.

Catatan pemeliharaan: ubah label/aksi pencarian pada `app_header.dart`, daftar menu pada `app_navbar.dart`, dan identitas sekolah ditentukan melalui parameter `AppFooter` dari navbar. Arahkan callback dari halaman pemanggil saat fitur navigasi, pencarian, atau notifikasi sudah dihubungkan ke aplikasi nyata.

Halaman login dan dialog ubah kata sandi berada di `lib/features/auth/views/`; `ApiClient` pada `lib/shared/services/api_client.dart` mengirim kredensial ke API dan menyimpan token hanya selama sesi aplikasi. Server memverifikasi kata sandi dan hanya menyimpan hash Argon2id. Jika menambah endpoint autentikasi, selaraskan DTO di klien, route di `backend/internal/httpapi`, validasi token, dan tes fixture HTTP.

`lib/shared/auth/role_permissions.dart` mengatur tampilan menu dan aksi UI: Admin mendapat seluruh fitur; Petugas dapat menambah aset, memperbarui kondisi, melihat/mencetak label, membuat/membatalkan/memposting draft mutasi, dan memperbarui pemeliharaan, tetapi tidak mengekspor laporan. Pimpinan bersifat baca-saja untuk operasional/master data dan dapat mengekspor laporan. Menu master data disembunyikan dari Petugas, sedangkan aksi edit master data hanya untuk Admin. Menu Pengguna dan semua aksi pengelolaan akun hanya untuk Admin. Backend mutasi memeriksa izin; alur persetujuan Pimpinan belum tersedia.

Halaman pengguna berada di `lib/features/users/`; backend juga membatasi endpoint pengelolaan akun ke Admin. Daftar memuat data dari API dan menampilkan maksimal 8 akun per halaman. Tambah akun meminta kata sandi awal yang hanya dikirim saat create; edit dan arsip baru memperbarui state setelah API berhasil. Nonaktifkan berarti arsip agar riwayat tetap terkait, bukan hapus akun. Reset password admin tetap mockup; API menyediakan perubahan kata sandi untuk akun yang sedang login, sedangkan reset oleh admin belum tersedia.

Penyembunyian menu/tombol adalah pengaturan UX, bukan pengganti otorisasi server. Endpoint inventaris, mutasi, dan pemeliharaan memeriksa izin baca/tulis pada server. Ekspor laporan masih pratinjau dan belum membuat file.

Halaman lokasi dan jenis/kategori berada di `lib/features/master_data/`. Lokasi memakai API `GET /api/v1/locations` untuk semua role yang terautentikasi; `POST`/`PATCH /api/v1/locations/{id}` hanya untuk Admin. Endpoint baca `GET /api/v1/item-kinds` dan `GET /api/v1/categories` juga terbuka untuk role terautentikasi, sementara create/update hanya Admin. Pimpinan dapat membaca dan Petugas tidak melihat menu master. Kode katalog dinormalisasi uppercase, kode harus unik, nama jenis/kategori dibatasi 120 karakter, dan deskripsi kategori 2000 karakter. Katalog dinonaktifkan sebagai arsip, bukan dihapus, agar referensi barang yang ada tetap bermakna. `database/mongo/init.js` menyediakan katalog awal jenis/kategori. Lokasi tidak di-seed karena struktur tiap sekolah berbeda; Admin membuat lokasi utama sendiri. Jika kontrak berubah, selaraskan form UI, `backend/internal/httpapi/catalog_handlers.go`, repository Mongo, dan validator/seed `database/mongo/init.js`.

Pada halaman inventaris, aksi **Ubah kondisi** memperbarui satu `asset_id`, meminta catatan wajib, dan menampilkan riwayat kondisi dari `asset_events`. Server mengambil pelaku dari token, menolak kondisi yang tidak berubah, serta membandingkan kondisi lama saat menyimpan agar perubahan bersamaan tidak saling menimpa. Perubahan aset dan event audit menggunakan operasi terpisah karena MongoDB standalone tidak mendukung transaksi; jika penyimpanan event gagal, backend mencoba memulihkan kondisi sebelumnya dan melaporkan kegagalan. Kondisi berlaku per unit aset, bukan semua unit dengan nama/kategori sama.

Kartu ringkasan inventaris menghitung total aset, kondisi bagus, perlu perhatian, dan aset rusak dari data server. Grafik kondisi juga menampilkan jumlah untuk `Bagus`, `Perlu perbaikan`, `Dalam service`, dan `Rusak`; perubahan katalog kondisi harus diselaraskan dengan label filter dan mapping UI.

Halaman pemeliharaan berada di `lib/features/maintenance/` dan memakai koleksi `maintenance_records` pada `database/mongo/init.js`. `GET /api/v1/maintenance-records` memuat daftar; `POST` membuat laporan untuk aset aktif; `PATCH /api/v1/maintenance-records/{id}` memulai, menyelesaikan, atau membatalkan laporan. Backend mengambil pelapor dari sesi, menetapkan waktu, memvalidasi transisi `reported` → `in_progress` → `completed` (atau dibatalkan sebelum terminal), dan memvalidasi biaya akhir. UI mengganti snapshot hanya setelah server menerima write. Status pemeliharaan tidak otomatis mengubah kondisi aset; pencatatan kondisi tetap dilakukan dari Inventaris.

Halaman laporan berada di `lib/features/reports/` dan memakai snapshot API untuk aset, mutasi, serta pemeliharaan. Filter periode memengaruhi mutasi dan tanggal laporan pemeliharaan; jumlah inventaris tidak dapat difilter berdasarkan tanggal karena model aset belum memiliki tanggal perolehan. Ringkasan tidak menampilkan saldo stok atau nilai total inventaris karena data kuantitas dan harga perolehan belum lengkap. Pratinjau ekspor menampilkan contoh dokumen PDF dan baris CSV dari bagian/filter aktif, tetapi belum membuat file. Backend/report service nantinya perlu menghasilkan PDF/CSV dengan escaping CSV yang benar dan data tervalidasi.

Label aset menggunakan barcode Code 128 yang memuat `InventoryItem.code` (kode aset dari server), bukan lokasi atau kondisi yang dapat berubah. Nama sekolah pada label ditelusuri dari lokasi aset ke parent teratas yang bertipe `sekolah`; struktur lokasi yang tidak lengkap ditandai sebagai `Nama sekolah belum diatur`. PDF label satu halaman berukuran 80 × 42 mm; tombol cetak membuka dialog sistem agar pengguna memilih printer dan media label. Setiap simpanan membuat satu unit/barcode; alur barang stok massal berada di luar cakupan halaman ini.

Halaman mutasi berada di `lib/features/movements/` dan memakai koleksi `stock_movements` serta `stock_movement_lines`. UI membaca riwayat dari API dan membuat/membatalkan/memposting draft satu barang per transaksi. Server menetapkan nomor, pelaku dari token, waktu, dan status; klien mengirim ID item/lokasi serta kunci idempotensi. Draft hanya menerima item/lokasi aktif, tipe penerimaan/pengeluaran/pemindahan/penyesuaian yang konsisten dengan lokasi, dan jumlah positif. Pembatalan hanya berlaku untuk draft dan tidak mengubah `stock_balances`. Posting tersedia melalui `PATCH /api/v1/movements/{id}/post`; backend memvalidasi saldo sumber dan memperbarui saldo, status, serta audit dalam satu transaksi. Header dan baris disimpan terpisah, sehingga Mongo standalone memakai penghapusan kompensasi jika simpan baris gagal. Gunakan replica set pengembangan untuk menguji posting.

## Menyiapkan database melalui Robo 3T

1. Pastikan layanan MongoDB Laragon berjalan.
2. Buat koneksi Robo 3T ke `localhost`, port `27017` (tanpa autentikasi untuk instalasi lokal saat ini).
3. Buka IntelliShell di Robo 3T, buka file `database/mongo/init.js`, lalu jalankan seluruh script.
4. Script membuat database `inventaris_sederhana`, koleksi, validator, indeks unik, dan data master awal. Script aman dijalankan ulang dan tidak menggandakan data master.
5. Segarkan daftar database di Robo 3T. URI untuk backend lokal:

   ```text
   mongodb://localhost:27017/inventaris_sederhana
   ```

Script inisialisasi database tidak membuat akun pengguna. Jalankan API pada server Windows 10/11 atau Linux; Windows 7 hanya digunakan sebagai klien. Backend Go modern dan MongoDB 8 tidak ditargetkan berjalan langsung di Windows 7.

## Menjalankan API Go

Pasang Go pada server dan siapkan koleksi MongoDB dengan `database/mongo/init.js`. API dapat memakai MongoDB standalone untuk login, pengguna, master data, aset, dan penyimpanan draft mutasi; pemostingan saldo stok akan membutuhkan replica set. Jangan buka port MongoDB ke jaringan.

Di PowerShell:

```powershell
cd backend
$bytes = New-Object byte[] 48
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$env:JWT_SECRET = [Convert]::ToBase64String($bytes)
$env:MONGODB_URI = "mongodb://127.0.0.1:27017"
$env:MONGODB_DATABASE = "inventaris_sederhana"
$env:HTTP_ADDR = "127.0.0.1:8081"
$env:CORS_ALLOWED_ORIGINS = "http://localhost:8080,http://127.0.0.1:8080,http://localhost:5173,http://127.0.0.1:5173"
# Jalankan satu kali; setelah admin dibuat, mulai API dengan perintah berikut.
go run ./cmd/bootstrap-admin
go run ./cmd/server
```

Variabel `JWT_SECRET` wajib berisi minimal 32 karakter acak; simpan di secret store untuk deployment dan jangan commit nilainya. `CORS_ALLOWED_ORIGINS` opsional berisi daftar origin Web yang dipisahkan koma; tanpa nilai khusus, API hanya mengizinkan origin loopback untuk Flutter Web pada port 8080 dan 5173. Secara default API hanya bind ke loopback.

Jalankan bootstrap **satu kali** di terminal yang sama setelah database diinisialisasi. Ini memakai konfigurasi `JWT_SECRET` dan MongoDB dari shell tersebut; kata sandi admin dibaca tanpa ditampilkan, harus 12–128 karakter, dan disimpan sebagai hash Argon2id. Setelah admin tersedia, jangan jalankan bootstrap lagi; jalankan `go run ./cmd/server` untuk memulai API.

Perintah bootstrap membuat admin jika belum ada, atau mengganti hash akun admin statis lama dari mockup. Perintah ini menolak menimpa admin aktif yang sudah memiliki kata sandi baru. Database kosong sebaiknya sudah diinisialisasi agar validator dan indeks unik tersedia.

Endpoint awal:

- `GET /healthz` — status API dan koneksi MongoDB.
- `POST /api/v1/auth/login` — memverifikasi akun aktif, mencatat login, dan mengembalikan bearer token 15 menit.
- `GET /api/v1/auth/me` — profil akun aktif dari token.
- `POST /api/v1/auth/change-password` — ganti kata sandi dengan verifikasi kata sandi saat ini.
- `GET /api/v1/users?page=1&page_size=20` — daftar akun, hanya admin.
- `POST /api/v1/users` — buat akun dengan kata sandi awal 12–128 karakter, hanya admin.
- `PATCH /api/v1/users/{id}` — ubah username, nama, peran, atau status aktif, hanya admin.
- `GET /api/v1/locations` — baca lokasi aktif dan arsip untuk semua peran yang terautentikasi.
- `POST /api/v1/locations` — tambah lokasi, hanya admin.
- `PATCH /api/v1/locations/{id}` — ubah field lokasi/status aktif, hanya admin.
- `GET /api/v1/item-kinds` — daftar jenis barang aktif dan arsip untuk semua role terautentikasi.
- `POST /api/v1/item-kinds` — tambah jenis barang, hanya admin.
- `PATCH /api/v1/item-kinds/{id}` — ubah jenis barang atau status aktif, hanya admin.
- `GET /api/v1/categories` — daftar kategori aktif dan arsip untuk semua role terautentikasi.
- `POST /api/v1/categories` — tambah kategori, hanya admin.
- `PATCH /api/v1/categories/{id}` — ubah kategori/deskripsi atau status aktif, hanya admin.
- `GET /api/v1/assets?page=1&page_size=20` — daftar aset aktif beserta riwayatnya untuk semua role terautentikasi.
- `POST /api/v1/assets` — buat satu unit aset; Admin dan Petugas. Body menerima `name`, `kind_id`, `category_id`, `location_id`, dan `condition` (label kondisi seed).
- `PATCH /api/v1/assets/{id}` — edit jenis, nama, kategori, lokasi, dan kondisi satu unit aset; Admin dan Petugas. Perubahan item induk dipisah dari unit lain yang berbagi item sebelumnya dan dicatat di riwayat.
- `PATCH /api/v1/assets/{id}/archive` — nonaktifkan aset dengan mengarsipkan status, mempertahankan barcode dan seluruh riwayat.
- `GET /api/v1/stock-items` — daftar barang habis pakai beserta saldo per lokasi.
- `POST /api/v1/stock-items` — buat barang habis pakai dan saldo awal; Admin dan Petugas. Body menerima `name`, `kind_id`, `category_id`, `unit`, `minimum_stock`, `location_id`, dan `initial_quantity`.
- `PATCH /api/v1/stock-items/{id}` — koreksi data barang dan jumlah pada satu lokasi; alasan wajib disimpan sebagai mutasi adjustment posted.
- `PATCH /api/v1/assets/{id}/condition` — ubah kondisi satu aset dengan catatan wajib; Admin dan Petugas. Body menerima `condition` dan `notes`.
- `GET /api/v1/movements?page=1&page_size=20` — daftar mutasi berhalaman untuk semua role terautentikasi.
- `POST /api/v1/movements` — simpan draft satu baris; Admin dan Petugas. Body menerima `movement_type`, `idempotency_key`, dan `line` berisi `item_id`, `from_location_id`, `to_location_id`, `quantity`, serta `notes`.
- `PATCH /api/v1/movements/{id}/cancel` — batalkan draft; Admin dan Petugas. Mutasi yang bukan draft ditolak.

Pembuatan aset menerima jenis barang aktif untuk aset (barang habis pakai dicatat lewat mutasi stok), kategori, dan lokasi aktif. Kode aset dibuat sebagai `KODE-SEKOLAH-KODE-KATEGORI-TAHUN-NOMOR`, dengan kode sekolah diambil dari lokasi induk berjenis sekolah dan nomor yang naik atomik per sekolah/kategori/tahun. Lokasi aset harus berada di bawah lokasi sekolah dengan kode terisi. Setelah menambah koleksi `asset_code_sequences` dan jenis event `asset_edited`, jalankan ulang `database/mongo/init.js` agar validator MongoDB diperbarui. Item induk yang nama + jenis + kategori sama digunakan kembali; penonaktifan aset hanya mengarsipkan unitnya.

Tab Barang Habis Pakai pada halaman Inventaris memakai `tracking_mode=stock`, satuan, batas minimum, dan saldo awal per lokasi. Stok awal belum membuat event mutasi; perubahan stok sesudahnya harus memakai alur posting mutasi, sementara draft mutasi yang ada tidak mengubah saldo.

Login menerima `{ "username": "...", "password": "..." }`. Buat pengguna menerima `username`, `full_name`, `role` (`admin`, `petugas`, `pimpinan`), dan `password`. Gunakan header `Authorization: Bearer <access_token>` untuk endpoint terlindungi. Token kedaluwarsa setelah 15 menit dan belum memiliki mekanisme refresh/revoke; perubahan kata sandi tidak membatalkan token yang sudah terbit, yang tetap berlaku paling lama hingga kedaluwarsa.

Respons API tidak pernah mengirim `password_hash`. Endpoint menolak field JSON yang tidak dikenal, membatasi body menjadi 1 MiB, menerapkan batas waktu HTTP, dan memakai allowlist CORS bila origin disetel. Sebelum API dibuka ke jaringan, terapkan pembatasan percobaan login di reverse proxy, pasang TLS, aktifkan autentikasi MongoDB dengan hak minimum, atur CORS secara eksplisit, dan siapkan backup.

## Alternatif: MongoDB lokal dengan transaksi

Transaksi multi-dokumen MongoDB memerlukan replica set. Instalasi MongoDB standalone tidak mendukung alur transaksi stok; gunakan replica set untuk menguji alur tersebut.

Jika Docker Desktop tersedia, konfigurasi opsional di `docker-compose.yml` membuat MongoDB 8 replica set satu node pada port `27018`, terpisah dari MongoDB Laragon:

```powershell
docker compose up -d
docker compose ps
docker compose logs mongodb-setup
```

URI backend untuk replica set Docker:

```text
mongodb://localhost:27018/inventaris_sederhana?replicaSet=rs0
```

Data Docker disimpan di volume `mongodb_data`; `docker compose down` tidak menghapusnya. `docker compose down --volumes` akan menghapus seluruh data Docker lokal.

Kedua konfigurasi lokal ini hanya untuk pengembangan dan tanpa autentikasi database. Port hanya diikat ke localhost. Jangan membuka MongoDB langsung ke jaringan atau internet. Untuk penggunaan selain lokal, siapkan autentikasi, kredensial berhak minimum, TLS, dan backup.

## Koleksi

- `users`, `login_events`
- `item_kinds`, `categories`, `conditions`, `locations`
- `items`, `assets`, `asset_events`
- `stock_movements`, `stock_movement_lines`, `stock_balances`
- `maintenance_records`, `audit_logs`

`database/mongo/init.js` memasang validasi field dan indeks unik, lalu mengisi jenis barang, kategori, dan kondisi awal. Validator menolak field yang tidak didefinisikan; perubahan skema harus ditambahkan ke script ini sebelum backend mulai menulis field baru.

ID dokumen menggunakan string agar mudah dipetakan ke Firestore. MongoDB tidak menerapkan foreign key; backend harus memvalidasi referensi seperti `parent_id`, `item_id`, dan `location_id`.

Riwayat dan baris mutasi disimpan sebagai dokumen terpisah, bukan array yang terus bertambah. Dokumen Firestore dibatasi 1 MiB, sehingga backend tetap harus membatasi ukuran payload dan dokumen saat implementasi. Audit log membatasi daftar perubahan hingga 25 field, dengan nilai sebelum/sesudah disimpan sebagai teks terbatas.

Draft mutasi menggunakan `idempotency_key` unik agar pengiriman ulang permintaan yang sama tidak menggandakan draft. Posting mutasi stok dilakukan backend Go dalam transaksi MongoDB: validasi saldo, ubah status dan saldo, lalu tulis audit log sebagai satu operasi atomik. Untuk menguji alur posting, gunakan replica set Docker; standalone Laragon tidak mendukung transaksi multi-dokumen. Replica set satu node hanya untuk pengembangan, bukan pengganti backup atau deployment produksi yang redundan.

Kata sandi aplikasi hanya disimpan di `users.password_hash` sebagai hash Argon2id; jangan menyimpan kata sandi asli atau mencatatnya ke log.
