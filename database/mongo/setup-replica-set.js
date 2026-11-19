// Nama replica set harus sama dengan nilai --replSet pada konfigurasi MongoDB.
var replicaSetName = "rs0";
// Alamat anggota replica set yang dipakai oleh aplikasi dari host komputer.
var replicaSetMember = "localhost:27018";
// Pemeriksaan dan inisialisasi replica set dilakukan melalui database admin.
var adminDatabase = db.getSiblingDB("admin");
var status = adminDatabase.runCommand({ replSetGetStatus: 1 });

// Inisialisasi hanya saat replica set belum aktif; aman dijalankan ulang.
if (status.ok !== 1) {
  var result = rs.initiate({
    _id: replicaSetName,
    members: [{ _id: 0, host: replicaSetMember }],
  });

  if (result.ok !== 1 && result.codeName !== "AlreadyInitialized") {
    throw new Error("Unable to initialize replica set: " + tojson(result));
  }
}

// Tunggu sampai pemilihan anggota utama selesai sebelum skrip init data dijalankan.
var isPrimary = false;
for (var attempt = 0; attempt < 60; attempt += 1) {
  var hello = adminDatabase.runCommand({ hello: 1 });
  if (hello.isWritablePrimary) {
    isPrimary = true;
    break;
  }
  sleep(1000);
}

if (!isPrimary) {
  throw new Error("MongoDB did not elect a primary within 60 seconds.");
}

// Pesan ini menandakan replica set siap menerima operasi tulis.
print("MongoDB replica set initialized: " + replicaSetName);
