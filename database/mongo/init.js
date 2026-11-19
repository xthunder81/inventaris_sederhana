// Pilih database aplikasi yang akan disiapkan oleh skrip inisialisasi ini.
var database = db.getSiblingDB("inventaris_sederhana");

// Helper untuk mendefinisikan aturan tipe string, panjang maksimum, dan pilihan nilai.
function stringField(maxLength, enumValues) {
  var field = { bsonType: "string", maxLength: maxLength };
  if (enumValues) {
    field.enum = enumValues;
  }
  return field;
}

// Helper untuk string yang boleh bernilai null.
function nullableStringField(maxLength) {
  return { bsonType: ["string", "null"], maxLength };
}

// Helper untuk angka dengan tipe BSON yang didukung dan batas minimum opsional.
function numberField(minimum) {
  var field = { bsonType: ["double", "int", "long", "decimal"] };
  if (minimum !== undefined) {
    field.minimum = minimum;
  }
  return field;
}

// Helper untuk angka yang juga boleh bernilai null.
function nullableNumberField(minimum) {
  var field = { bsonType: ["double", "int", "long", "decimal", "null"] };
  if (minimum !== undefined) {
    field.minimum = minimum;
  }
  return field;
}

// Bentuk setiap perubahan pada audit log; properti tambahan tidak diperbolehkan.
var auditChangeSchema = {
  bsonType: "object",
  additionalProperties: false,
  required: ["field", "before", "after"],
  properties: {
    field: stringField(64),
    before: nullableStringField(2048),
    after: nullableStringField(2048),
  },
};

// Skema memvalidasi bentuk dokumen sebelum MongoDB menerima data ke koleksi.
// Setiap koleksi mencantumkan field wajib serta aturan untuk field yang dikenal.
var schemas = {
  // Akun pengguna aplikasi dan informasi status login.
  users: {
    required: ["username", "full_name", "password_hash", "role", "is_active", "created_at"],
    properties: {
      username: stringField(128),
      full_name: stringField(200),
      password_hash: stringField(255),
      role: stringField(32, ["admin", "petugas", "pimpinan"]),
      is_active: { bsonType: "bool" },
      last_login_at: { bsonType: ["date", "null"] },
      created_at: { bsonType: "date" },
      updated_at: { bsonType: "date" },
    },
  },
  // Riwayat percobaan login, baik yang berhasil maupun gagal.
  login_events: {
    required: ["user_id", "username", "result", "occurred_at"],
    properties: {
      user_id: nullableStringField(64),
      username: stringField(128),
      result: stringField(16, ["success", "failed"]),
      occurred_at: { bsonType: "date" },
    },
  },
  // Jenis barang, misalnya barang habis pakai atau aset.
  item_kinds: {
    required: ["code", "name", "is_active"],
    properties: {
      code: stringField(64),
      name: stringField(120),
      is_active: { bsonType: "bool" },
    },
  },
  // Kategori untuk mengelompokkan barang.
  categories: {
    required: ["code", "name", "description", "is_active"],
    properties: {
      code: stringField(64),
      name: stringField(120),
      description: stringField(2000),
      is_active: { bsonType: "bool" },
    },
  },
  // Daftar kondisi barang/aset.
  conditions: {
    required: ["code", "name", "is_active"],
    properties: {
      code: stringField(64),
      name: stringField(120),
      is_active: { bsonType: "bool" },
    },
  },
  // Struktur lokasi bertingkat, seperti sekolah, gedung, ruang, atau gudang.
  locations: {
    required: ["code", "name", "parent_id", "location_type", "is_active"],
    properties: {
      code: stringField(64),
      name: stringField(200),
      parent_id: nullableStringField(64),
      location_type: stringField(32, ["sekolah", "gedung", "ruang", "gudang", "area", "lainnya"]),
      is_active: { bsonType: "bool" },
      created_at: { bsonType: "date" },
      updated_at: { bsonType: "date" },
    },
  },
  // Data induk barang; detail unit aset dan stok disimpan di koleksi terpisah.
  items: {
    required: [
      "item_code",
      "name",
      "item_kind_id",
      "category_id",
      "tracking_mode",
      "unit",
      "minimum_stock",
      "is_active",
      "created_at",
      "updated_at",
    ],
    properties: {
      item_code: stringField(64),
      name: stringField(200),
      item_kind_id: stringField(64),
      category_id: stringField(64),
      tracking_mode: stringField(16, ["asset", "stock"]),
      unit: stringField(32),
      minimum_stock: numberField(0),
      is_active: { bsonType: "bool" },
      created_at: { bsonType: "date" },
      updated_at: { bsonType: "date" },
    },
  },
  // Urutan kode aset atomik per kode sekolah, kategori, dan tahun.
  asset_code_sequences: {
    required: ["value"],
    properties: { value: numberField(1) },
  },
  // Unit aset individual yang dapat dilacak berdasarkan kode dan lokasi.
  assets: {
    required: [
      "item_id",
      "asset_code",
      "location_id",
      "condition_id",
      "asset_status",
      "created_at",
      "updated_at",
    ],
    properties: {
      item_id: stringField(64),
      asset_code: stringField(64),
      serial_number: stringField(256),
      location_id: stringField(64),
      condition_id: stringField(64),
      asset_status: stringField(16, ["active", "archived", "disposed"]),
      acquisition_date: { bsonType: ["date", "null"] },
      acquisition_cost: nullableNumberField(0),
      created_at: { bsonType: "date" },
      updated_at: { bsonType: "date" },
    },
  },
  // Riwayat perubahan kondisi atau lokasi suatu aset.
  asset_events: {
    required: [
      "asset_id",
      "event_type",
      "previous_condition_id",
      "new_condition_id",
      "from_location_id",
      "to_location_id",
      "performed_by",
      "notes",
      "occurred_at",
    ],
    properties: {
      asset_id: stringField(64),
      event_type: stringField(32, [
        "received",
        "transferred",
        "condition_changed",
        "asset_edited",
        "archived",
        "disposed",
        "maintenance",
      ]),
      previous_condition_id: nullableStringField(64),
      new_condition_id: nullableStringField(64),
      from_location_id: nullableStringField(64),
      to_location_id: nullableStringField(64),
      performed_by: stringField(64),
      notes: stringField(2000),
      occurred_at: { bsonType: "date" },
    },
  },
  // Transaksi stok, termasuk status dan informasi pembuatannya.
  stock_movements: {
    required: [
      "movement_number",
      "movement_type",
      "status",
      "idempotency_key",
      "performed_by",
      "created_at",
    ],
    properties: {
      movement_number: stringField(64),
      movement_type: stringField(16, ["receipt", "issue", "transfer", "adjustment"]),
      status: stringField(16, ["draft", "posted", "cancelled"]),
      idempotency_key: stringField(128),
      performed_by: stringField(64),
      created_at: { bsonType: "date" },
      posted_at: { bsonType: ["date", "null"] },
    },
  },
  // Rincian barang dan kuantitas untuk setiap transaksi stok.
  stock_movement_lines: {
    required: [
      "movement_id",
      "line_number",
      "item_id",
      "from_location_id",
      "to_location_id",
      "quantity",
      "notes",
    ],
    properties: {
      movement_id: stringField(64),
      line_number: { bsonType: ["int", "long"], minimum: 1 },
      item_id: stringField(64),
      from_location_id: nullableStringField(64),
      to_location_id: nullableStringField(64),
      quantity: numberField(0.000001),
      notes: stringField(1000),
    },
  },
  // Saldo stok per kombinasi barang dan lokasi.
  stock_balances: {
    required: ["item_id", "location_id", "quantity", "updated_at"],
    properties: {
      item_id: stringField(64),
      location_id: stringField(64),
      quantity: numberField(0),
      updated_at: { bsonType: "date" },
    },
  },
  // Laporan dan proses pemeliharaan aset.
  maintenance_records: {
    required: [
      "asset_id",
      "reported_by",
      "status",
      "description",
      "cost",
      "reported_at",
      "closed_at",
    ],
    properties: {
      asset_id: stringField(64),
      reported_by: stringField(64),
      status: stringField(16, ["reported", "in_progress", "completed", "cancelled"]),
      description: stringField(4000),
      cost: numberField(0),
      reported_at: { bsonType: "date" },
      closed_at: { bsonType: ["date", "null"] },
    },
  },
  // Catatan aktivitas pengguna dan perubahan data untuk keperluan audit.
  audit_logs: {
    required: [
      "actor_id",
      "action",
      "entity_type",
      "entity_id",
      "changes",
      "occurred_at",
    ],
    properties: {
      actor_id: stringField(64),
      action: stringField(16, ["create", "update", "archive", "delete"]),
      entity_type: stringField(64),
      entity_id: stringField(64),
      changes: {
        bsonType: "array",
        maxItems: 25,
        items: auditChangeSchema,
      },
      occurred_at: { bsonType: "date" },
    },
  },
};

// Tambahkan aturan _id dan tolak field yang tidak didefinisikan di skema.
// Skema koleksi yang sudah ada diperbarui; koleksi yang belum ada dibuat.
Object.keys(schemas).forEach(function (collectionName) {
  var schema = schemas[collectionName];
  schema.properties._id = stringField(64);
  schema.additionalProperties = false;

  var collectionExists = database
    .getCollectionInfos({ name: collectionName })
    .length > 0;

  if (collectionExists) {
    database.runCommand({
      collMod: collectionName,
      validator: { $jsonSchema: schema },
      validationLevel: "strict",
      validationAction: "error",
    });
  } else {
    database.createCollection(collectionName, {
      validator: { $jsonSchema: schema },
      validationLevel: "strict",
      validationAction: "error",
    });
  }
});

// Indeks mempercepat pencarian, sedangkan indeks unique mencegah nilai duplikat.
var indexDefinitions = {
  users: [
    { key: { username: 1 }, options: { unique: true, name: "uq_users_username" } },
    { key: { role: 1, is_active: 1 }, options: { name: "ix_users_role_active" } },
  ],
  login_events: [
    { key: { user_id: 1, occurred_at: -1 }, options: { name: "ix_login_events_user_time" } },
    { key: { occurred_at: -1 }, options: { name: "ix_login_events_time" } },
  ],
  item_kinds: [
    { key: { code: 1 }, options: { unique: true, name: "uq_item_kinds_code" } },
  ],
  categories: [
    { key: { code: 1 }, options: { unique: true, name: "uq_categories_code" } },
  ],
  conditions: [
    { key: { code: 1 }, options: { unique: true, name: "uq_conditions_code" } },
  ],
  locations: [
    { key: { code: 1 }, options: { unique: true, name: "uq_locations_code" } },
    { key: { parent_id: 1, is_active: 1 }, options: { name: "ix_locations_parent_active" } },
  ],
  items: [
    { key: { item_code: 1 }, options: { unique: true, name: "uq_items_code" } },
    { key: { category_id: 1, is_active: 1 }, options: { name: "ix_items_category_active" } },
    { key: { item_kind_id: 1, is_active: 1 }, options: { name: "ix_items_kind_active" } },
  ],
  assets: [
    { key: { asset_code: 1 }, options: { unique: true, name: "uq_assets_code" } },
    { key: { serial_number: 1 }, options: { unique: true, sparse: true, name: "uq_assets_serial" } },
    { key: { item_id: 1, asset_status: 1 }, options: { name: "ix_assets_item_status" } },
    { key: { location_id: 1, condition_id: 1 }, options: { name: "ix_assets_location_condition" } },
    // Endpoint daftar aset menyaring status lalu mengurutkan tanggal terbaru.
    { key: { asset_status: 1, created_at: -1, _id: 1 }, options: { name: "ix_assets_status_created" } },
  ],
  asset_events: [
    { key: { asset_id: 1, occurred_at: -1 }, options: { name: "ix_asset_events_asset_time" } },
    // Riwayat halaman inventaris diambil per aset dengan waktu/event terbaru dulu.
    { key: { asset_id: 1, occurred_at: -1, _id: -1 }, options: { name: "ix_asset_events_asset_time_id" } },
    { key: { performed_by: 1, occurred_at: -1 }, options: { name: "ix_asset_events_user_time" } },
  ],
  stock_movements: [
    { key: { movement_number: 1 }, options: { unique: true, name: "uq_stock_movements_number" } },
    { key: { idempotency_key: 1 }, options: { unique: true, name: "uq_stock_movements_idempotency" } },
    { key: { status: 1, created_at: -1 }, options: { name: "ix_stock_movements_status_time" } },
  ],
  stock_movement_lines: [
    {
      key: { movement_id: 1, line_number: 1 },
      options: { unique: true, name: "uq_stock_movement_lines_number" },
    },
    { key: { item_id: 1, movement_id: 1 }, options: { name: "ix_stock_movement_lines_item" } },
  ],
  stock_balances: [
    {
      key: { item_id: 1, location_id: 1 },
      options: { unique: true, name: "uq_stock_balances_item_location" },
    },
  ],
  maintenance_records: [
    { key: { asset_id: 1, reported_at: -1 }, options: { name: "ix_maintenance_asset_time" } },
    { key: { status: 1, reported_at: -1 }, options: { name: "ix_maintenance_status_time" } },
  ],
  audit_logs: [
    { key: { entity_type: 1, entity_id: 1, occurred_at: -1 }, options: { name: "ix_audit_entity_time" } },
    { key: { actor_id: 1, occurred_at: -1 }, options: { name: "ix_audit_actor_time" } },
  ],
};

// Terapkan seluruh definisi indeks ke koleksi masing-masing.
Object.keys(indexDefinitions).forEach(function (collectionName) {
  var definitions = indexDefinitions[collectionName];
  var collection = database.getCollection(collectionName);
  definitions.forEach(function (definition) {
    collection.createIndex(definition.key, definition.options);
  });
});

// Tambahkan data katalog hanya jika kode belum ditemukan; data yang ada tidak ditimpa.
function seedCatalog(collectionName, documents) {
  var collection = database.getCollection(collectionName);
  documents.forEach(function (document) {
    var seedDocument = {};
    Object.keys(document).forEach(function (key) {
      seedDocument[key] = document[key];
    });
    seedDocument.is_active = true;
    collection.updateOne(
      { code: document.code },
      { $setOnInsert: seedDocument },
      { upsert: true }
    );
  });
}

// Katalog awal jenis barang.
seedCatalog("item_kinds", [
  {
    _id: "00000000-0000-4000-8000-000000000001",
    code: "habis_pakai",
    name: "Barang Habis Pakai",
  },
  {
    _id: "00000000-0000-4000-8000-000000000002",
    code: "tidak_habis_pakai",
    name: "Barang Tidak Habis Pakai",
  },
  {
    _id: "00000000-0000-4000-8000-000000000003",
    code: "lainnya",
    name: "Lainnya",
  },
]);

// Katalog awal kategori barang.
seedCatalog("categories", [
  {
    _id: "00000000-0000-4000-8000-000000000101",
    code: "elektronik",
    name: "Elektronik",
    description: "",
  },
  {
    _id: "00000000-0000-4000-8000-000000000102",
    code: "atk",
    name: "Alat Tulis Kantor",
    description: "",
  },
  {
    _id: "00000000-0000-4000-8000-000000000103",
    code: "mebel",
    name: "Mebel",
    description: "",
  },
  {
    _id: "00000000-0000-4000-8000-000000000104",
    code: "alat_olahraga",
    name: "Alat Olahraga",
    description: "",
  },
  {
    _id: "00000000-0000-4000-8000-000000000105",
    code: "lainnya",
    name: "Lainnya",
    description: "",
  },
]);

// Katalog awal kondisi aset.
seedCatalog("conditions", [
  {
    _id: "00000000-0000-4000-8000-000000000201",
    code: "bagus",
    name: "Bagus",
  },
  {
    _id: "00000000-0000-4000-8000-000000000202",
    code: "perlu_perbaikan",
    name: "Perlu Perbaikan",
  },
  {
    _id: "00000000-0000-4000-8000-000000000203",
    code: "dalam_service",
    name: "Dalam Service",
  },
  {
    _id: "00000000-0000-4000-8000-000000000204",
    code: "rusak",
    name: "Rusak",
  },
]);

print("MongoDB initialized: inventaris_sederhana");
