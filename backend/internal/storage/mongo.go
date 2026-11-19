package storage

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"

	"inventaris_sederhana/backend/internal/inventory"
	"inventaris_sederhana/backend/internal/locations"
	"inventaris_sederhana/backend/internal/masterdata"
	"inventaris_sederhana/backend/internal/movements"
	"inventaris_sederhana/backend/internal/users"
)

// CATATAN PEMELIHARAAN: semua field yang ditulis di sini harus tetap cocok
// dengan validator ketat pada database/mongo/init.js; ubah keduanya bersama.
type Mongo struct {
	client *mongo.Client
	db     *mongo.Database
}

// CATATAN PEMELIHARAAN: koneksi melakukan ping sebelum dipakai agar server
// gagal cepat jika MongoDB mati atau URI/database salah; timeout dikendalikan
// oleh ctx pemanggil dan selection timeout 8 detik.
func Connect(ctx context.Context, uri, database string) (*Mongo, error) {
	client, err := mongo.Connect(ctx, options.Client().
		ApplyURI(uri).
		SetServerSelectionTimeout(8*time.Second))
	if err != nil {
		return nil, fmt.Errorf("hubungkan MongoDB: %w", err)
	}
	if err := client.Ping(ctx, readpref.Primary()); err != nil {
		_ = client.Disconnect(context.Background())
		return nil, fmt.Errorf("MongoDB tidak merespons: %w", err)
	}
	return &Mongo{client: client, db: client.Database(database)}, nil
}

// CATATAN PEMELIHARAAN: panggil saat shutdown agar pool koneksi dilepas;
// pemanggil tetap harus mencatat kegagalan disconnect.
func (store *Mongo) Close(ctx context.Context) error {
	return store.client.Disconnect(ctx)
}

// CATATAN PEMELIHARAAN: dipakai health endpoint untuk membedakan API hidup
// dengan layanan yang juga dapat mencapai MongoDB.
func (store *Mongo) Ping(ctx context.Context) error {
	return store.client.Ping(ctx, readpref.Primary())
}

// CATATAN PEMELIHARAAN: username sudah dinormalisasi handler ke huruf kecil;
// indeks unik users.username menjadi sumber kebenaran untuk konflik akun.
func (store *Mongo) FindByUsername(ctx context.Context, username string) (users.User, error) {
	var user users.User
	err := store.db.Collection("users").FindOne(ctx, bson.M{"username": username}).Decode(&user)
	return user, translateNotFound(err)
}

// CATATAN PEMELIHARAAN: ID adalah string UUID, bukan ObjectID; bila strategi
// ID berubah, token sub dan semua referensi pengguna harus dimigrasikan bersama.
func (store *Mongo) FindByID(ctx context.Context, id string) (users.User, error) {
	var user users.User
	err := store.db.Collection("users").FindOne(ctx, bson.M{"_id": id}).Decode(&user)
	return user, translateNotFound(err)
}

// CATATAN PEMELIHARAAN: urutan stabil dibuat dari created_at dan _id agar
// pagination tidak berpindah acak. Limit dan skip divalidasi di API sebelum
// query; pertimbangkan cursor pagination bila jumlah akun bertambah besar.
func (store *Mongo) List(ctx context.Context, skip, limit int64) ([]users.User, error) {
	cursor, err := store.db.Collection("users").Find(
		ctx,
		bson.M{},
		options.Find().
			SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: 1}}).
			SetSkip(skip).
			SetLimit(limit),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil daftar pengguna: %w", err)
	}
	defer cursor.Close(ctx)
	result := make([]users.User, 0)
	if err := cursor.All(ctx, &result); err != nil {
		return nil, fmt.Errorf("baca daftar pengguna: %w", err)
	}
	return result, nil
}

// CATATAN PEMELIHARAAN: count dipakai bersama List untuk total pagination;
// filter akun harus diterapkan sama pada kedua query bila daftar kelak difilter.
func (store *Mongo) Count(ctx context.Context) (int64, error) {
	count, err := store.db.Collection("users").CountDocuments(ctx, bson.D{})
	if err != nil {
		return 0, fmt.Errorf("hitung pengguna: %w", err)
	}
	return count, nil
}

// CATATAN PEMELIHARAAN: ID baru dibuat di backend dan indeks unik menolak
// username duplikat. Field yang ditulis harus lolos validator users di init.js.
func (store *Mongo) Create(ctx context.Context, user users.User) error {
	if user.ID == "" {
		user.ID = uuid.NewString()
	}
	if _, err := store.db.Collection("users").InsertOne(ctx, user); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return users.ErrConflict
		}
		return fmt.Errorf("simpan pengguna: %w", err)
	}
	return nil
}

// CATATAN PEMELIHARAAN: hanya field yang lolos validasi API dimasukkan ke
// $set; indeks unik memvalidasi username. Jika audit diwajibkan atomik bersama
// perubahan akun, gunakan replica set dan transaksi, bukan operasi terpisah.
func (store *Mongo) Update(ctx context.Context, id string, update users.Update) (users.User, error) {
	fields := bson.M{"updated_at": time.Now().UTC()}
	if update.Username != nil {
		fields["username"] = *update.Username
	}
	if update.FullName != nil {
		fields["full_name"] = *update.FullName
	}
	if update.Role != nil {
		fields["role"] = *update.Role
	}
	if update.IsActive != nil {
		fields["is_active"] = *update.IsActive
	}
	result, err := store.db.Collection("users").UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": fields},
	)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return users.User{}, users.ErrConflict
		}
		return users.User{}, fmt.Errorf("ubah pengguna: %w", err)
	}
	if result.MatchedCount == 0 {
		return users.User{}, users.ErrNotFound
	}
	return store.FindByID(ctx, id)
}

// CATATAN PEMELIHARAAN: hanya hash Argon2id yang diterima; perubahan password
// tidak mengubah session JWT yang sudah terbit, yang tetap berlaku sampai exp.
func (store *Mongo) UpdatePassword(ctx context.Context, id, passwordHash string) error {
	result, err := store.db.Collection("users").UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{
			"password_hash": passwordHash,
			"updated_at":    time.Now().UTC(),
		}},
	)
	if err != nil {
		return fmt.Errorf("ubah kata sandi: %w", err)
	}
	if result.MatchedCount == 0 {
		return users.ErrNotFound
	}
	return nil
}

// CATATAN PEMELIHARAAN: waktu login terakhir dan updated_at mengikuti satu
// timestamp UTC dari handler agar response dan record konsisten.
func (store *Mongo) UpdateLastLogin(ctx context.Context, id string, at time.Time) error {
	result, err := store.db.Collection("users").UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{"last_login_at": at, "updated_at": at}},
	)
	if err != nil {
		return fmt.Errorf("perbarui waktu login: %w", err)
	}
	if result.MatchedCount == 0 {
		return users.ErrNotFound
	}
	return nil
}

// CATATAN PEMELIHARAAN: hanya username, hasil, user ID opsional, dan waktu
// disimpan; jangan menambah password atau token ke login_events.
func (store *Mongo) RecordLogin(ctx context.Context, event users.LoginEvent) error {
	eventID := uuid.NewString()
	_, err := store.db.Collection("login_events").InsertOne(ctx, bson.M{
		"_id":         eventID,
		"user_id":     event.UserID,
		"username":    event.Username,
		"result":      event.Result,
		"occurred_at": event.OccurredAt,
	})
	if err != nil {
		return fmt.Errorf("catat aktivitas login: %w", err)
	}
	return nil
}

// CATATAN PEMELIHARAAN: daftar seluruh lokasi karena halaman master perlu
// menampilkan arsip sekaligus aktif; bila jumlahnya besar, tambah paginasi
// server dan pertahankan total pada kontrak API.
func (store *Mongo) ListLocations(ctx context.Context) ([]locations.Location, error) {
	cursor, err := store.db.Collection("locations").Find(
		ctx,
		bson.D{},
		options.Find().SetSort(bson.D{{Key: "code", Value: 1}, {Key: "_id", Value: 1}}),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil daftar lokasi: %w", err)
	}
	defer cursor.Close(ctx)
	result := make([]locations.Location, 0)
	if err := cursor.All(ctx, &result); err != nil {
		return nil, fmt.Errorf("baca daftar lokasi: %w", err)
	}
	return result, nil
}

// CATATAN PEMELIHARAAN: ID dan waktu dibuat handler, sedangkan indeks unik
// locations.code tetap menjadi perlindungan terakhir terhadap duplikasi.
func (store *Mongo) CreateLocation(ctx context.Context, location locations.Location) error {
	if _, err := store.db.Collection("locations").InsertOne(ctx, location); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return locations.ErrConflict
		}
		return fmt.Errorf("simpan lokasi: %w", err)
	}
	return nil
}

// CATATAN PEMELIHARAAN: hanya field lokasi yang sudah divalidasi handler
// ditulis; updated_at membantu audit ringan dan tetap sesuai schema init.js.
func (store *Mongo) UpdateLocation(ctx context.Context, id string, location locations.Location) (locations.Location, error) {
	result, err := store.db.Collection("locations").UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{
			"code":          location.Code,
			"name":          location.Name,
			"parent_id":     location.ParentID,
			"location_type": location.LocationType,
			"is_active":     location.IsActive,
			"updated_at":    location.UpdatedAt,
		}},
	)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return locations.Location{}, locations.ErrConflict
		}
		return locations.Location{}, fmt.Errorf("ubah lokasi: %w", err)
	}
	if result.MatchedCount == 0 {
		return locations.Location{}, locations.ErrNotFound
	}
	var updated locations.Location
	if err := store.db.Collection("locations").FindOne(ctx, bson.M{"_id": id}).Decode(&updated); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return locations.Location{}, locations.ErrNotFound
		}
		return locations.Location{}, fmt.Errorf("baca lokasi yang diubah: %w", err)
	}
	return updated, nil
}

// CATATAN PEMELIHARAAN: katalog berukuran kecil sehingga API memuat seluruh
// daftar untuk pencarian/paginasi lokal; pertahankan sort stabil dan tambahkan
// pagination server bila jumlah jenis barang bertambah besar.
func (store *Mongo) ListItemKinds(ctx context.Context) ([]masterdata.ItemKind, error) {
	cursor, err := store.db.Collection("item_kinds").Find(
		ctx,
		bson.D{},
		options.Find().SetSort(bson.D{{Key: "code", Value: 1}, {Key: "_id", Value: 1}}),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil daftar jenis barang: %w", err)
	}
	defer cursor.Close(ctx)
	result := make([]masterdata.ItemKind, 0)
	if err := cursor.All(ctx, &result); err != nil {
		return nil, fmt.Errorf("baca daftar jenis barang: %w", err)
	}
	return result, nil
}

// CATATAN PEMELIHARAAN: ID dibuat handler dan indeks unique code menjadi
// perlindungan terakhir terhadap request create bersamaan.
func (store *Mongo) CreateItemKind(ctx context.Context, item masterdata.ItemKind) error {
	if _, err := store.db.Collection("item_kinds").InsertOne(ctx, item); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return masterdata.ErrConflict
		}
		return fmt.Errorf("simpan jenis barang: %w", err)
	}
	return nil
}

// CATATAN PEMELIHARAAN: update memakai $set terbatas pada field item_kinds
// yang tervalidasi API; indeks kode unik menerjemahkan duplikasi menjadi 409.
func (store *Mongo) UpdateItemKind(ctx context.Context, id string, item masterdata.ItemKind) (masterdata.ItemKind, error) {
	result, err := store.db.Collection("item_kinds").UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{
			"code":      item.Code,
			"name":      item.Name,
			"is_active": item.IsActive,
		}},
	)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return masterdata.ItemKind{}, masterdata.ErrConflict
		}
		return masterdata.ItemKind{}, fmt.Errorf("ubah jenis barang: %w", err)
	}
	if result.MatchedCount == 0 {
		return masterdata.ItemKind{}, masterdata.ErrNotFound
	}
	var updated masterdata.ItemKind
	if err := store.db.Collection("item_kinds").FindOne(ctx, bson.M{"_id": id}).Decode(&updated); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return masterdata.ItemKind{}, masterdata.ErrNotFound
		}
		return masterdata.ItemKind{}, fmt.Errorf("baca jenis barang yang diubah: %w", err)
	}
	return updated, nil
}

// CATATAN PEMELIHARAAN: kategori dimuat terpisah dari jenis karena deskripsi
// hanya bagian schema categories; jangan gabungkan collection tanpa migrasi.
func (store *Mongo) ListCategories(ctx context.Context) ([]masterdata.Category, error) {
	cursor, err := store.db.Collection("categories").Find(
		ctx,
		bson.D{},
		options.Find().SetSort(bson.D{{Key: "code", Value: 1}, {Key: "_id", Value: 1}}),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil daftar kategori: %w", err)
	}
	defer cursor.Close(ctx)
	result := make([]masterdata.Category, 0)
	if err := cursor.All(ctx, &result); err != nil {
		return nil, fmt.Errorf("baca daftar kategori: %w", err)
	}
	return result, nil
}

// CATATAN PEMELIHARAAN: description selalu disimpan, termasuk string kosong,
// agar dokumen tetap lolos schema categories yang mewajibkan field tersebut.
func (store *Mongo) CreateCategory(ctx context.Context, category masterdata.Category) error {
	if _, err := store.db.Collection("categories").InsertOne(ctx, category); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return masterdata.ErrConflict
		}
		return fmt.Errorf("simpan kategori: %w", err)
	}
	return nil
}

// CATATAN PEMELIHARAAN: perubahan kategori dibatasi ke empat field katalog;
// data barang yang merujuk category_id tidak ikut diubah saat arsip/edit.
func (store *Mongo) UpdateCategory(ctx context.Context, id string, category masterdata.Category) (masterdata.Category, error) {
	result, err := store.db.Collection("categories").UpdateOne(
		ctx,
		bson.M{"_id": id},
		bson.M{"$set": bson.M{
			"code":        category.Code,
			"name":        category.Name,
			"description": category.Description,
			"is_active":   category.IsActive,
		}},
	)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return masterdata.Category{}, masterdata.ErrConflict
		}
		return masterdata.Category{}, fmt.Errorf("ubah kategori: %w", err)
	}
	if result.MatchedCount == 0 {
		return masterdata.Category{}, masterdata.ErrNotFound
	}
	var updated masterdata.Category
	if err := store.db.Collection("categories").FindOne(ctx, bson.M{"_id": id}).Decode(&updated); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return masterdata.Category{}, masterdata.ErrNotFound
		}
		return masterdata.Category{}, fmt.Errorf("baca kategori yang diubah: %w", err)
	}
	return updated, nil
}

type assetDocument struct {
	ID          string    `bson:"_id"`
	ItemID      string    `bson:"item_id"`
	AssetCode   string    `bson:"asset_code"`
	LocationID  string    `bson:"location_id"`
	ConditionID string    `bson:"condition_id"`
	AssetStatus string    `bson:"asset_status"`
	CreatedAt   time.Time `bson:"created_at"`
}

type inventoryItemDocument struct {
	ID           string  `bson:"_id"`
	Code         string  `bson:"item_code"`
	Name         string  `bson:"name"`
	KindID       string  `bson:"item_kind_id"`
	CategoryID   string  `bson:"category_id"`
	Unit         string  `bson:"unit"`
	MinimumStock float64 `bson:"minimum_stock"`
}

type inventoryCategoryDocument struct {
	ID   string `bson:"_id"`
	Code string `bson:"code"`
	Name string `bson:"name"`
}

type inventoryLocationDocument struct {
	ID           string  `bson:"_id"`
	Code         string  `bson:"code"`
	Name         string  `bson:"name"`
	ParentID     *string `bson:"parent_id"`
	LocationType string  `bson:"location_type"`
}

type inventoryConditionDocument struct {
	ID   string `bson:"_id"`
	Code string `bson:"code"`
	Name string `bson:"name"`
}

type assetEventDocument struct {
	AssetID             string    `bson:"asset_id"`
	EventType           string    `bson:"event_type"`
	PreviousConditionID *string   `bson:"previous_condition_id"`
	NewConditionID      *string   `bson:"new_condition_id"`
	PerformedBy         string    `bson:"performed_by"`
	Notes               string    `bson:"notes"`
	OccurredAt          time.Time `bson:"occurred_at"`
}

type inventoryUserDocument struct {
	ID       string `bson:"_id"`
	FullName string `bson:"full_name"`
}

// CATATAN PEMELIHARAAN: kode aset memakai kode sekolah induk, kode kategori,
// tahun kalender saat pencatatan, dan urutan atomik per prefix. Indeks unik
// assets.asset_code tetap menjadi pagar terakhir bila counter tidak sinkron.
func (store *Mongo) schoolCodeForLocation(ctx context.Context, location inventoryLocationDocument) (string, error) {
	current := location
	seen := map[string]bool{}
	for depth := 0; depth < 32; depth++ {
		if current.LocationType == "sekolah" {
			if code := normalizeAssetCodePart(current.Code); code != "" {
				return code, nil
			}
			return "", errors.New("kode lokasi sekolah kosong")
		}
		if current.ParentID == nil || seen[*current.ParentID] {
			break
		}
		seen[*current.ParentID] = true
		var parent inventoryLocationDocument
		if err := store.db.Collection("locations").FindOne(ctx, bson.M{"_id": *current.ParentID}).Decode(&parent); err != nil {
			return "", fmt.Errorf("baca sekolah induk lokasi: %w", err)
		}
		current = parent
	}
	return "", errors.New("lokasi aset tidak memiliki lokasi induk berjenis sekolah")
}

func normalizeAssetCodePart(value string) string {
	var result strings.Builder
	lastDash := false
	for _, r := range strings.ToUpper(strings.TrimSpace(value)) {
		if r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' {
			result.WriteRune(r)
			lastDash = false
		} else if !lastDash && result.Len() > 0 {
			result.WriteByte('-')
			lastDash = true
		}
	}
	return strings.Trim(result.String(), "-")
}

func (store *Mongo) nextAssetCode(ctx context.Context, schoolCode, categoryCode string, year int) (string, error) {
	schoolCode = normalizeAssetCodePart(schoolCode)
	categoryCode = normalizeAssetCodePart(categoryCode)
	if len(schoolCode)+len(categoryCode) > 47 {
		return "", errors.New("gabungan kode sekolah dan kategori terlalu panjang untuk kode aset")
	}
	prefix := fmt.Sprintf("%s-%s-%04d", schoolCode, categoryCode, year)
	var counter struct {
		Value int64 `bson:"value"`
	}
	err := store.db.Collection("asset_code_sequences").FindOneAndUpdate(ctx, bson.M{"_id": prefix}, bson.M{"$inc": bson.M{"value": 1}}, options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After)).Decode(&counter)
	if err != nil {
		return "", fmt.Errorf("ambil urutan kode aset: %w", err)
	}
	return fmt.Sprintf("%s-%04d", prefix, counter.Value), nil
}

// CATATAN PEMELIHARAAN: pagination menghitung dan membaca aset aktif saja;
// riwayat tetap dipaginasikan bersama aset halaman tersebut agar API tidak
// carik seluruh inventaris ke klien dalam satu response.
func (store *Mongo) CountAssets(ctx context.Context) (int64, error) {
	count, err := store.db.Collection("assets").CountDocuments(ctx, bson.M{"asset_status": "active"})
	if err != nil {
		return 0, fmt.Errorf("hitung aset aktif: %w", err)
	}
	return count, nil
}

// CATATAN PEMELIHARAAN: skip/limit diterima dari handler setelah parsePage;
// data master dan seluruh event untuk aset pada halaman digabungkan di
// inventoryRecords agar UI tidak melakukan request tambahan per baris.
func (store *Mongo) ListAssets(ctx context.Context, skip, limit int64) ([]inventory.Record, error) {
	cursor, err := store.db.Collection("assets").Find(
		ctx,
		bson.M{"asset_status": "active"},
		options.Find().
			SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: 1}}).
			SetSkip(skip).
			SetLimit(limit),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil halaman aset: %w", err)
	}
	defer cursor.Close(ctx)
	assets := make([]assetDocument, 0)
	if err := cursor.All(ctx, &assets); err != nil {
		return nil, fmt.Errorf("baca halaman aset: %w", err)
	}
	return store.inventoryRecords(ctx, assets)
}

// CATATAN PEMELIHARAAN: semua referensi aktif divalidasi ulang di Mongo. Item
// induk digunakan ulang berdasarkan nama + jenis + kategori; setiap unit punya
// barcode dengan kode sekolah, kategori, tahun, dan nomor urut atomik.
func (store *Mongo) CreateAsset(
	ctx context.Context,
	input inventory.CreateInput,
	actorID string,
	actorName string,
) (inventory.Record, error) {
	var category inventoryCategoryDocument
	if err := store.db.Collection("categories").FindOne(ctx, bson.M{
		"_id": input.CategoryID, "is_active": true,
	}).Decode(&category); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	var location inventoryLocationDocument
	if err := store.db.Collection("locations").FindOne(ctx, bson.M{
		"_id": input.LocationID, "is_active": true,
	}).Decode(&location); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	schoolCode, err := store.schoolCodeForLocation(ctx, location)
	if err != nil {
		return inventory.Record{}, err
	}
	var kind masterdata.ItemKind
	if err := store.db.Collection("item_kinds").FindOne(ctx, bson.M{
		"_id": input.KindID, "is_active": true,
	}).Decode(&kind); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	if strings.EqualFold(kind.Code, "habis_pakai") {
		return inventory.Record{}, inventory.ErrInvalidReference
	}
	var condition inventoryConditionDocument
	if err := store.db.Collection("conditions").FindOne(ctx, bson.M{
		"code": input.ConditionCode, "is_active": true,
	}).Decode(&condition); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}

	itemCollection := store.db.Collection("items")
	var item inventoryItemDocument
	itemFilter := bson.M{
		"name": input.Name, "item_kind_id": kind.ID, "category_id": category.ID,
		"tracking_mode": "asset", "is_active": true,
	}
	err = itemCollection.FindOne(ctx, itemFilter).Decode(&item)
	if errors.Is(err, mongo.ErrNoDocuments) {
		now := time.Now().UTC()
		item = inventoryItemDocument{
			ID:         uuid.NewString(),
			Name:       input.Name,
			CategoryID: category.ID,
		}
		itemCode := "ITM-" + strings.ToUpper(strings.ReplaceAll(item.ID, "-", "")[:12])
		if _, insertErr := itemCollection.InsertOne(ctx, bson.M{
			"_id": item.ID, "item_code": itemCode, "name": item.Name,
			"item_kind_id": kind.ID, "category_id": category.ID,
			"tracking_mode": "asset", "unit": "unit", "minimum_stock": 0,
			"is_active": true, "created_at": now, "updated_at": now,
		}); insertErr != nil {
			if mongo.IsDuplicateKeyError(insertErr) {
				return inventory.Record{}, inventory.ErrConflict
			}
			return inventory.Record{}, fmt.Errorf("simpan data induk barang: %w", insertErr)
		}
	} else if err != nil {
		return inventory.Record{}, fmt.Errorf("cari data induk barang: %w", err)
	}

	now := time.Now().UTC()
	assetID := uuid.NewString()
	assetCode, err := store.nextAssetCode(ctx, schoolCode, category.Code, now.Year())
	if err != nil {
		return inventory.Record{}, err
	}
	asset := assetDocument{
		ID: assetID, ItemID: item.ID, AssetCode: assetCode,
		LocationID: location.ID, ConditionID: condition.ID,
		AssetStatus: "active", CreatedAt: now,
	}
	if _, err := store.db.Collection("assets").InsertOne(ctx, bson.M{
		"_id": asset.ID, "item_id": asset.ItemID, "asset_code": asset.AssetCode,
		"location_id": asset.LocationID, "condition_id": asset.ConditionID,
		"asset_status": asset.AssetStatus, "created_at": now, "updated_at": now,
	}); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return inventory.Record{}, inventory.ErrConflict
		}
		return inventory.Record{}, fmt.Errorf("simpan unit aset: %w", err)
	}
	// CATATAN PEMELIHARAAN: setiap koleksi memakai _id string sesuai schema
	// Mongo. Beri ID eksplisit pada event; tanpa ini driver membuat ObjectId,
	// sehingga event gagal divalidasi setelah dokumen item dan aset tersimpan.
	if _, err := store.db.Collection("asset_events").InsertOne(ctx, bson.M{
		"_id": uuid.NewString(), "asset_id": asset.ID, "event_type": "received",
		"previous_condition_id": nil, "new_condition_id": condition.ID,
		"from_location_id": nil, "to_location_id": location.ID,
		"performed_by": actorID, "notes": "Aset didaftarkan.",
		"occurred_at": now,
	}); err != nil {
		cleanupContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if _, cleanupErr := store.db.Collection("assets").DeleteOne(cleanupContext, bson.M{"_id": asset.ID}); cleanupErr != nil {
			return inventory.Record{}, fmt.Errorf("catat pendaftaran aset: %v; hapus aset yang gagal dicatat: %w", err, cleanupErr)
		}
		return inventory.Record{}, fmt.Errorf("catat pendaftaran aset: %w", err)
	}

	return inventory.Record{
		AssetID: asset.ID, ItemID: item.ID, KindID: kind.ID, AssetCode: asset.AssetCode,
		Name: item.Name, CategoryID: category.ID, Category: category.Name,
		LocationID: location.ID, Location: location.Name,
		ConditionID: condition.ID, Condition: inventoryConditionLabel(condition),
		CreatedAt: now,
		Events: []inventory.EventView{{
			EventType: "received", NewCondition: inventoryConditionLabel(condition),
			PerformedBy: actorName, Notes: "Aset didaftarkan.", OccurredAt: now,
		}},
	}, nil
}

// CATATAN PEMELIHARAAN: perbandingan condition_id di filter update mencegah
// dua petugas menimpa perubahan satu sama lain. Event disimpan setelah update;
// jika insert event gagal, kondisi lama dipulihkan tanpa transaksi Mongo.
func (store *Mongo) ChangeAssetCondition(
	ctx context.Context,
	assetID string,
	conditionCode string,
	notes string,
	actorID string,
	actorName string,
) (inventory.Record, error) {
	var asset assetDocument
	if err := store.db.Collection("assets").FindOne(ctx, bson.M{
		"_id": assetID, "asset_status": "active",
	}).Decode(&asset); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return inventory.Record{}, inventory.ErrNotFound
		}
		return inventory.Record{}, fmt.Errorf("baca aset sebelum ubah kondisi: %w", err)
	}
	var condition inventoryConditionDocument
	if err := store.db.Collection("conditions").FindOne(ctx, bson.M{
		"code": conditionCode, "is_active": true,
	}).Decode(&condition); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	if asset.ConditionID == condition.ID {
		return inventory.Record{}, inventory.ErrConditionSame
	}
	records, err := store.inventoryRecords(ctx, []assetDocument{asset})
	if err != nil {
		return inventory.Record{}, err
	}
	if len(records) != 1 {
		return inventory.Record{}, errors.New("aset tidak menghasilkan record tampilan")
	}
	record := records[0]
	previousCondition := record.Condition
	oldConditionID := asset.ConditionID
	now := time.Now().UTC()
	result, err := store.db.Collection("assets").UpdateOne(ctx,
		bson.M{
			"_id": asset.ID, "asset_status": "active",
			"condition_id": oldConditionID,
		},
		bson.M{"$set": bson.M{"condition_id": condition.ID, "updated_at": now}},
	)
	if err != nil {
		return inventory.Record{}, fmt.Errorf("ubah kondisi aset: %w", err)
	}
	if result.MatchedCount == 0 {
		return inventory.Record{}, inventory.ErrConcurrentEdit
	}
	if _, err := store.db.Collection("asset_events").InsertOne(ctx, bson.M{
		// CATATAN PEMELIHARAAN: validator `init.js` mensyaratkan _id string;
		// UUID harus dibuat eksplisit agar Mongo tidak memasang ObjectID bawaan.
		"_id":      uuid.NewString(),
		"asset_id": asset.ID, "event_type": "condition_changed",
		"previous_condition_id": oldConditionID, "new_condition_id": condition.ID,
		"from_location_id": nil, "to_location_id": nil,
		"performed_by": actorID, "notes": notes, "occurred_at": now,
	}); err != nil {
		cleanupContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		rollbackResult, rollbackErr := store.db.Collection("assets").UpdateOne(cleanupContext,
			bson.M{"_id": asset.ID, "condition_id": condition.ID},
			bson.M{"$set": bson.M{"condition_id": oldConditionID, "updated_at": now}},
		)
		if rollbackErr != nil {
			return inventory.Record{}, fmt.Errorf("catat perubahan kondisi: %v; pulihkan kondisi lama: %w", err, rollbackErr)
		}
		if rollbackResult.MatchedCount == 0 {
			return inventory.Record{}, fmt.Errorf("catat perubahan kondisi: %v; kondisi aset berubah bersamaan sehingga pemulihan tidak diterapkan", err)
		}
		return inventory.Record{}, fmt.Errorf("catat perubahan kondisi: %w", err)
	}
	record.ConditionID = condition.ID
	record.Condition = inventoryConditionLabel(condition)
	record.Events = append([]inventory.EventView{{
		EventType:         "condition_changed",
		PreviousCondition: previousCondition,
		NewCondition:      inventoryConditionLabel(condition),
		PerformedBy:       actorName, Notes: notes, OccurredAt: now,
	}}, record.Events...)
	return record, nil
}

// CATATAN PEMELIHARAAN: nama/kategori berada di item induk yang dapat dipakai
// banyak unit. Saat mengedit satu unit, buat item induk baru jika perlu agar
// perubahan tidak merambat ke barcode lain; kondisi/lokasi tetap milik aset.
func (store *Mongo) UpdateAsset(ctx context.Context, id string, input inventory.UpdateInput, actorID, actorName string) (inventory.Record, error) {
	var asset assetDocument
	if err := store.db.Collection("assets").FindOne(ctx, bson.M{"_id": id, "asset_status": "active"}).Decode(&asset); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return inventory.Record{}, inventory.ErrNotFound
		}
		return inventory.Record{}, fmt.Errorf("baca aset: %w", err)
	}
	var category inventoryCategoryDocument
	if err := store.db.Collection("categories").FindOne(ctx, bson.M{"_id": input.CategoryID, "is_active": true}).Decode(&category); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	var location inventoryLocationDocument
	if err := store.db.Collection("locations").FindOne(ctx, bson.M{"_id": input.LocationID, "is_active": true}).Decode(&location); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	var condition inventoryConditionDocument
	if err := store.db.Collection("conditions").FindOne(ctx, bson.M{"code": input.ConditionCode, "is_active": true}).Decode(&condition); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	var kind masterdata.ItemKind
	if err := store.db.Collection("item_kinds").FindOne(ctx, bson.M{"_id": input.KindID, "is_active": true}).Decode(&kind); err != nil {
		return inventory.Record{}, invalidInventoryReference(err)
	}
	if strings.EqualFold(kind.Code, "habis_pakai") {
		return inventory.Record{}, inventory.ErrInvalidReference
	}
	oldRecords, err := store.inventoryRecords(ctx, []assetDocument{asset})
	if err != nil || len(oldRecords) != 1 {
		if err != nil {
			return inventory.Record{}, err
		}
		return inventory.Record{}, errors.New("record aset tidak ditemukan")
	}
	old := oldRecords[0]
	var oldItem inventoryItemDocument
	if err := store.db.Collection("items").FindOne(ctx, bson.M{"_id": asset.ItemID}).Decode(&oldItem); err != nil {
		return inventory.Record{}, fmt.Errorf("baca item induk: %w", err)
	}
	itemID := asset.ItemID
	if oldItem.Name != input.Name || old.CategoryID != category.ID || oldItem.KindID != input.KindID {
		var kind masterdata.ItemKind
		if err := store.db.Collection("item_kinds").FindOne(ctx, bson.M{"_id": input.KindID, "is_active": true}).Decode(&kind); err != nil {
			return inventory.Record{}, invalidInventoryReference(err)
		}
		var target inventoryItemDocument
		err := store.db.Collection("items").FindOne(ctx, bson.M{"name": input.Name, "item_kind_id": kind.ID, "category_id": category.ID, "tracking_mode": "asset", "is_active": true}).Decode(&target)
		if errors.Is(err, mongo.ErrNoDocuments) {
			itemID = uuid.NewString()
			now := time.Now().UTC()
			code := "ITM-" + strings.ToUpper(strings.ReplaceAll(itemID, "-", "")[:12])
			if _, err = store.db.Collection("items").InsertOne(ctx, bson.M{"_id": itemID, "item_code": code, "name": input.Name, "item_kind_id": kind.ID, "category_id": category.ID, "tracking_mode": "asset", "unit": "unit", "minimum_stock": 0, "is_active": true, "created_at": now, "updated_at": now}); err != nil {
				return inventory.Record{}, fmt.Errorf("simpan item hasil edit: %w", err)
			}
		} else if err != nil {
			return inventory.Record{}, fmt.Errorf("cari item hasil edit: %w", err)
		} else {
			itemID = target.ID
		}
	}
	now := time.Now().UTC()
	update := bson.M{"item_id": itemID, "location_id": location.ID, "condition_id": condition.ID, "updated_at": now}
	res, err := store.db.Collection("assets").UpdateOne(ctx, bson.M{"_id": id, "asset_status": "active", "item_id": asset.ItemID, "location_id": asset.LocationID, "condition_id": asset.ConditionID}, bson.M{"$set": update})
	if err != nil {
		return inventory.Record{}, fmt.Errorf("ubah aset: %w", err)
	}
	if res.MatchedCount == 0 {
		return inventory.Record{}, inventory.ErrConcurrentEdit
	}
	if _, err = store.db.Collection("asset_events").InsertOne(ctx, bson.M{"_id": uuid.NewString(), "asset_id": id, "event_type": "asset_edited", "previous_condition_id": asset.ConditionID, "new_condition_id": condition.ID, "from_location_id": asset.LocationID, "to_location_id": location.ID, "performed_by": actorID, "notes": "Data aset diperbarui.", "occurred_at": now}); err != nil {
		rollbackContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		rollback, rollbackErr := store.db.Collection("assets").UpdateOne(rollbackContext,
			bson.M{"_id": id, "item_id": itemID, "location_id": location.ID, "condition_id": condition.ID},
			bson.M{"$set": bson.M{"item_id": asset.ItemID, "location_id": asset.LocationID, "condition_id": asset.ConditionID, "updated_at": now}},
		)
		if rollbackErr != nil {
			return inventory.Record{}, fmt.Errorf("catat perubahan aset: %v; pulihkan data lama: %w", err, rollbackErr)
		}
		if rollback.MatchedCount == 0 {
			return inventory.Record{}, fmt.Errorf("catat perubahan aset: %v; data berubah bersamaan sehingga pemulihan tidak diterapkan", err)
		}
		return inventory.Record{}, fmt.Errorf("catat perubahan aset: %w", err)
	}
	asset.ItemID = itemID
	asset.LocationID = location.ID
	asset.ConditionID = condition.ID
	records, err := store.inventoryRecords(ctx, []assetDocument{asset})
	if err != nil {
		return inventory.Record{}, err
	}
	if len(records) != 1 {
		return inventory.Record{}, errors.New("record aset hasil edit tidak ditemukan")
	}
	_ = actorName
	return records[0], nil
}

// CATATAN PEMELIHARAAN: aset diarsipkan dengan perubahan status atomik lalu
// diberi event audit; dokumen tidak dihapus karena dipakai riwayat/mutasi.
func (store *Mongo) ArchiveAsset(ctx context.Context, id, actorID, _ string) error {
	var asset assetDocument
	if err := store.db.Collection("assets").FindOne(ctx, bson.M{"_id": id, "asset_status": "active"}).Decode(&asset); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return inventory.ErrNotFound
		}
		return fmt.Errorf("baca aset sebelum arsip: %w", err)
	}
	now := time.Now().UTC()
	updated, err := store.db.Collection("assets").UpdateOne(ctx, bson.M{"_id": id, "asset_status": "active"}, bson.M{"$set": bson.M{"asset_status": "archived", "updated_at": now}})
	if err != nil {
		return fmt.Errorf("nonaktifkan aset: %w", err)
	}
	if updated.MatchedCount == 0 {
		return inventory.ErrConcurrentEdit
	}
	if _, err = store.db.Collection("asset_events").InsertOne(ctx, bson.M{"_id": uuid.NewString(), "asset_id": id, "event_type": "archived", "previous_condition_id": asset.ConditionID, "new_condition_id": asset.ConditionID, "from_location_id": asset.LocationID, "to_location_id": asset.LocationID, "performed_by": actorID, "notes": "Aset dinonaktifkan.", "occurred_at": now}); err != nil {
		rollback, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		res, rollbackErr := store.db.Collection("assets").UpdateOne(rollback, bson.M{"_id": id, "asset_status": "archived"}, bson.M{"$set": bson.M{"asset_status": "active", "updated_at": now}})
		if rollbackErr != nil {
			return fmt.Errorf("catat penonaktifan: %v; pulihkan status aktif: %w", err, rollbackErr)
		}
		if res.MatchedCount == 0 {
			return fmt.Errorf("catat penonaktifan: %v; status aset berubah bersamaan sehingga pemulihan tidak diterapkan", err)
		}
		return fmt.Errorf("catat penonaktifan: %w", err)
	}
	return nil
}

type stockBalanceDocument struct {
	ID         string    `bson:"_id"`
	ItemID     string    `bson:"item_id"`
	LocationID string    `bson:"location_id"`
	Quantity   float64   `bson:"quantity"`
	UpdatedAt  time.Time `bson:"updated_at"`
}

// CATATAN PEMELIHARAAN: hanya item tracking_mode=stock muncul di tab kedua;
// saldo digabung per lokasi agar stok sekolah tidak tertukar antar ruang.
func (store *Mongo) ListStockItems(ctx context.Context) ([]inventory.StockItem, error) {
	cursor, err := store.db.Collection("items").Find(ctx, bson.M{"tracking_mode": "stock", "is_active": true}, options.Find().SetSort(bson.D{{Key: "name", Value: 1}, {Key: "_id", Value: 1}}))
	if err != nil {
		return nil, fmt.Errorf("ambil barang stok: %w", err)
	}
	defer cursor.Close(ctx)
	items := make([]inventoryItemDocument, 0)
	if err := cursor.All(ctx, &items); err != nil {
		return nil, fmt.Errorf("baca barang stok: %w", err)
	}
	if len(items) == 0 {
		return []inventory.StockItem{}, nil
	}
	itemIDs := make([]string, 0, len(items))
	categoryIDs := make([]string, 0, len(items))
	for _, item := range items {
		itemIDs = append(itemIDs, item.ID)
		categoryIDs = append(categoryIDs, item.CategoryID)
	}
	categories := make([]inventoryCategoryDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("categories"), categoryIDs, &categories); err != nil {
		return nil, err
	}
	categoryByID := make(map[string]inventoryCategoryDocument, len(categories))
	for _, category := range categories {
		categoryByID[category.ID] = category
	}
	balances := make([]stockBalanceDocument, 0)
	balanceCursor, err := store.db.Collection("stock_balances").Find(ctx, bson.M{"item_id": bson.M{"$in": itemIDs}})
	if err != nil {
		return nil, fmt.Errorf("ambil saldo barang: %w", err)
	}
	if err := balanceCursor.All(ctx, &balances); err != nil {
		balanceCursor.Close(ctx)
		return nil, fmt.Errorf("baca saldo barang: %w", err)
	}
	if err := balanceCursor.Close(ctx); err != nil {
		return nil, err
	}
	locationIDs := make([]string, 0, len(balances))
	for _, balance := range balances {
		locationIDs = append(locationIDs, balance.LocationID)
	}
	locations := make([]inventoryLocationDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("locations"), locationIDs, &locations); err != nil {
		return nil, err
	}
	locationByID := make(map[string]inventoryLocationDocument, len(locations))
	for _, location := range locations {
		locationByID[location.ID] = location
	}
	balancesByItem := make(map[string][]inventory.StockBalance, len(items))
	for _, balance := range balances {
		location, ok := locationByID[balance.LocationID]
		if !ok {
			return nil, fmt.Errorf("lokasi saldo %s tidak ditemukan", balance.LocationID)
		}
		balancesByItem[balance.ItemID] = append(balancesByItem[balance.ItemID], inventory.StockBalance{LocationID: location.ID, Location: location.Name, Quantity: balance.Quantity, UpdatedAt: balance.UpdatedAt})
	}
	result := make([]inventory.StockItem, 0, len(items))
	for _, item := range items {
		category, ok := categoryByID[item.CategoryID]
		if !ok {
			return nil, fmt.Errorf("kategori barang stok %s tidak ditemukan", item.ID)
		}
		result = append(result, inventory.StockItem{ItemID: item.ID, Code: item.Code, Name: item.Name, KindID: item.KindID, CategoryID: item.CategoryID, Category: category.Name, Unit: item.Unit, MinimumStock: item.MinimumStock, Balances: balancesByItem[item.ID]})
	}
	return result, nil
}

// CATATAN PEMELIHARAAN: saldo awal disimpan per lokasi bersama item katalog;
// bila saldo insert gagal, item yatim dibersihkan agar UI tidak melaporkan
// barang berhasil dibuat tanpa jumlah stok yang dipilih pengguna.
func (store *Mongo) CreateStockItem(ctx context.Context, input inventory.StockItemInput) (inventory.StockItem, error) {
	var kind masterdata.ItemKind
	if err := store.db.Collection("item_kinds").FindOne(ctx, bson.M{"_id": input.KindID, "is_active": true}).Decode(&kind); err != nil {
		return inventory.StockItem{}, invalidInventoryReference(err)
	}
	if !strings.EqualFold(kind.Code, "habis_pakai") {
		return inventory.StockItem{}, inventory.ErrInvalidReference
	}
	var category inventoryCategoryDocument
	if err := store.db.Collection("categories").FindOne(ctx, bson.M{"_id": input.CategoryID, "is_active": true}).Decode(&category); err != nil {
		return inventory.StockItem{}, invalidInventoryReference(err)
	}
	var location inventoryLocationDocument
	if err := store.db.Collection("locations").FindOne(ctx, bson.M{"_id": input.LocationID, "is_active": true}).Decode(&location); err != nil {
		return inventory.StockItem{}, invalidInventoryReference(err)
	}
	var duplicate inventoryItemDocument
	if err := store.db.Collection("items").FindOne(ctx, bson.M{"name": input.Name, "item_kind_id": kind.ID, "category_id": category.ID, "tracking_mode": "stock", "is_active": true}).Decode(&duplicate); err == nil {
		return inventory.StockItem{}, inventory.ErrConflict
	} else if !errors.Is(err, mongo.ErrNoDocuments) {
		return inventory.StockItem{}, fmt.Errorf("periksa barang stok duplikat: %w", err)
	}
	now := time.Now().UTC()
	id := uuid.NewString()
	code := "STK-" + strings.ToUpper(strings.ReplaceAll(id, "-", "")[:12])
	doc := bson.M{"_id": id, "item_code": code, "name": input.Name, "item_kind_id": kind.ID, "category_id": category.ID, "tracking_mode": "stock", "unit": input.Unit, "minimum_stock": input.MinimumStock, "is_active": true, "created_at": now, "updated_at": now}
	if _, err := store.db.Collection("items").InsertOne(ctx, doc); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return inventory.StockItem{}, inventory.ErrConflict
		}
		return inventory.StockItem{}, fmt.Errorf("simpan barang stok: %w", err)
	}
	if _, err := store.db.Collection("stock_balances").InsertOne(ctx, bson.M{"_id": uuid.NewString(), "item_id": id, "location_id": location.ID, "quantity": input.InitialQuantity, "updated_at": now}); err != nil {
		cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if _, cleanupErr := store.db.Collection("items").DeleteOne(cleanup, bson.M{"_id": id}); cleanupErr != nil {
			return inventory.StockItem{}, fmt.Errorf("simpan saldo awal: %v; hapus barang yatim: %w", err, cleanupErr)
		}
		return inventory.StockItem{}, fmt.Errorf("simpan saldo awal: %w", err)
	}
	return inventory.StockItem{ItemID: id, Code: code, Name: input.Name, KindID: kind.ID, CategoryID: category.ID, Category: category.Name, Unit: input.Unit, MinimumStock: input.MinimumStock, Balances: []inventory.StockBalance{{LocationID: location.ID, Location: location.Name, Quantity: input.InitialQuantity, UpdatedAt: now}}}, nil
}

// CATATAN PEMELIHARAAN: jumlah diedit sebagai adjustment yang langsung
// diposting per item/lokasi. Saldo dibandingkan atomik dan dikembalikan jika
// header/baris adjustment gagal. Jika pembaruan metadata gagal sesudahnya,
// saldo tetap tercatat sebagai adjustment sehingga riwayat tidak dipalsukan.
func (store *Mongo) UpdateStockItem(ctx context.Context, id string, input inventory.StockItemUpdateInput, actorID string) (inventory.StockItem, error) {
	var item inventoryItemDocument
	if err := store.db.Collection("items").FindOne(ctx, bson.M{"_id": id, "tracking_mode": "stock", "is_active": true}).Decode(&item); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return inventory.StockItem{}, inventory.ErrNotFound
		}
		return inventory.StockItem{}, fmt.Errorf("baca barang stok sebelum edit: %w", err)
	}
	var category inventoryCategoryDocument
	if err := store.db.Collection("categories").FindOne(ctx, bson.M{"_id": input.CategoryID, "is_active": true}).Decode(&category); err != nil {
		return inventory.StockItem{}, invalidInventoryReference(err)
	}
	var location inventoryLocationDocument
	if err := store.db.Collection("locations").FindOne(ctx, bson.M{"_id": input.LocationID, "is_active": true}).Decode(&location); err != nil {
		return inventory.StockItem{}, invalidInventoryReference(err)
	}
	var duplicate inventoryItemDocument
	if err := store.db.Collection("items").FindOne(ctx, bson.M{"_id": bson.M{"$ne": id}, "name": input.Name, "item_kind_id": item.KindID, "category_id": category.ID, "tracking_mode": "stock", "is_active": true}).Decode(&duplicate); err == nil {
		return inventory.StockItem{}, inventory.ErrConflict
	} else if !errors.Is(err, mongo.ErrNoDocuments) {
		return inventory.StockItem{}, fmt.Errorf("periksa barang stok duplikat: %w", err)
	}
	var balance stockBalanceDocument
	if err := store.db.Collection("stock_balances").FindOne(ctx, bson.M{"item_id": id, "location_id": location.ID}).Decode(&balance); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return inventory.StockItem{}, inventory.ErrInvalidReference
		}
		return inventory.StockItem{}, fmt.Errorf("baca saldo sebelum koreksi: %w", err)
	}
	if input.Quantity != balance.Quantity {
		now := time.Now().UTC()
		updated, err := store.db.Collection("stock_balances").UpdateOne(ctx, bson.M{"_id": balance.ID, "item_id": id, "location_id": location.ID, "quantity": balance.Quantity}, bson.M{"$set": bson.M{"quantity": input.Quantity, "updated_at": now}})
		if err != nil {
			return inventory.StockItem{}, fmt.Errorf("koreksi saldo stok: %w", err)
		}
		if updated.MatchedCount == 0 {
			return inventory.StockItem{}, inventory.ErrConcurrentEdit
		}
		movementID := uuid.NewString()
		idem := uuid.NewString()
		movementNumber := fmt.Sprintf("MUT-%d-%s", now.Year(), strings.ToUpper(strings.ReplaceAll(movementID, "-", "")[:12]))
		if _, err = store.db.Collection("stock_movements").InsertOne(ctx, bson.M{"_id": movementID, "movement_number": movementNumber, "movement_type": "adjustment", "status": "posted", "idempotency_key": idem, "performed_by": actorID, "created_at": now, "posted_at": now}); err != nil {
			if rollbackErr := store.rollbackStockCorrection(ctx, id, location.ID, balance.Quantity, input.Quantity, balance.UpdatedAt); rollbackErr != nil {
				return inventory.StockItem{}, fmt.Errorf("catat koreksi saldo: %v; pulihkan saldo awal: %w", err, rollbackErr)
			}
			return inventory.StockItem{}, fmt.Errorf("catat koreksi saldo: %w", err)
		}
		delta := math.Abs(input.Quantity - balance.Quantity)
		note := fmt.Sprintf("Koreksi saldo dari %s menjadi %s; alasan: %s", formatStockQuantity(balance.Quantity), formatStockQuantity(input.Quantity), input.Notes)
		if _, err = store.db.Collection("stock_movement_lines").InsertOne(ctx, bson.M{"_id": uuid.NewString(), "movement_id": movementID, "line_number": 1, "item_id": id, "from_location_id": nil, "to_location_id": location.ID, "quantity": delta, "notes": note}); err != nil {
			cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, headerErr := store.db.Collection("stock_movements").DeleteOne(cleanup, bson.M{"_id": movementID, "status": "posted"})
			rollbackErr := store.rollbackStockCorrection(cleanup, id, location.ID, balance.Quantity, input.Quantity, balance.UpdatedAt)
			if rollbackErr != nil {
				return inventory.StockItem{}, fmt.Errorf("catat baris koreksi: %v; pulihkan saldo awal: %w", err, rollbackErr)
			}
			if headerErr != nil {
				return inventory.StockItem{}, fmt.Errorf("catat baris koreksi: %v; hapus header koreksi: %w", err, headerErr)
			}
			return inventory.StockItem{}, fmt.Errorf("catat baris koreksi saldo: %w", err)
		}
	}
	result, err := store.db.Collection("items").UpdateOne(ctx, bson.M{"_id": id, "tracking_mode": "stock", "is_active": true}, bson.M{"$set": bson.M{"name": input.Name, "category_id": category.ID, "unit": input.Unit, "minimum_stock": input.MinimumStock, "updated_at": time.Now().UTC()}})
	if err != nil {
		if input.Quantity != balance.Quantity {
			return inventory.StockItem{}, fmt.Errorf("ubah data barang stok setelah koreksi saldo: %w; saldo telah dicatat sebagai adjustment", err)
		}
		return inventory.StockItem{}, fmt.Errorf("ubah data barang stok: %w", err)
	}
	if result.MatchedCount == 0 {
		if input.Quantity != balance.Quantity {
			return inventory.StockItem{}, fmt.Errorf("%w; saldo telah dicatat sebagai adjustment", inventory.ErrConcurrentEdit)
		}
		return inventory.StockItem{}, inventory.ErrConcurrentEdit
	}
	items, err := store.ListStockItems(ctx)
	if err != nil {
		return inventory.StockItem{}, err
	}
	for _, updated := range items {
		if updated.ItemID == id {
			return updated, nil
		}
	}
	return inventory.StockItem{}, inventory.ErrNotFound
}

func formatStockQuantity(value float64) string { return strconv.FormatFloat(value, 'f', -1, 64) }

func (store *Mongo) rollbackStockCorrection(ctx context.Context, itemID, locationID string, oldQuantity, newQuantity float64, oldUpdatedAt time.Time) error {
	result, err := store.db.Collection("stock_balances").UpdateOne(ctx, bson.M{"item_id": itemID, "location_id": locationID, "quantity": newQuantity}, bson.M{"$set": bson.M{"quantity": oldQuantity, "updated_at": oldUpdatedAt}})
	if err != nil {
		return err
	}
	if result.MatchedCount == 0 {
		return inventory.ErrConcurrentEdit
	}
	return nil
}

// CATATAN PEMELIHARAAN: gabungkan ID dari assets ke items, categories,
// locations, conditions, users, dan asset_events. Saat validator/DTO Mongo
// berubah, perbarui document struct dan mapping respons di fungsi ini bersama.
func (store *Mongo) inventoryRecords(ctx context.Context, assets []assetDocument) ([]inventory.Record, error) {
	if len(assets) == 0 {
		return []inventory.Record{}, nil
	}
	assetIDs := make([]string, 0, len(assets))
	itemIDs := make([]string, 0, len(assets))
	locationIDs := make([]string, 0, len(assets))
	conditionIDs := make([]string, 0, len(assets))
	seenItems := map[string]bool{}
	seenLocations := map[string]bool{}
	seenConditions := map[string]bool{}
	for _, asset := range assets {
		assetIDs = append(assetIDs, asset.ID)
		if !seenItems[asset.ItemID] {
			itemIDs = append(itemIDs, asset.ItemID)
			seenItems[asset.ItemID] = true
		}
		if !seenLocations[asset.LocationID] {
			locationIDs = append(locationIDs, asset.LocationID)
			seenLocations[asset.LocationID] = true
		}
		if !seenConditions[asset.ConditionID] {
			conditionIDs = append(conditionIDs, asset.ConditionID)
			seenConditions[asset.ConditionID] = true
		}
	}

	items := make([]inventoryItemDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("items"), itemIDs, &items); err != nil {
		return nil, err
	}
	itemByID := make(map[string]inventoryItemDocument, len(items))
	categoryIDs := make([]string, 0, len(items))
	seenCategories := map[string]bool{}
	for _, item := range items {
		itemByID[item.ID] = item
		if !seenCategories[item.CategoryID] {
			categoryIDs = append(categoryIDs, item.CategoryID)
			seenCategories[item.CategoryID] = true
		}
	}
	categories := make([]inventoryCategoryDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("categories"), categoryIDs, &categories); err != nil {
		return nil, err
	}
	categoryByID := make(map[string]inventoryCategoryDocument, len(categories))
	for _, category := range categories {
		categoryByID[category.ID] = category
	}
	locations := make([]inventoryLocationDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("locations"), locationIDs, &locations); err != nil {
		return nil, err
	}
	locationByID := make(map[string]inventoryLocationDocument, len(locations))
	for _, location := range locations {
		locationByID[location.ID] = location
	}
	conditions := make([]inventoryConditionDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("conditions"), conditionIDs, &conditions); err != nil {
		return nil, err
	}
	conditionByID := make(map[string]inventoryConditionDocument, len(conditions))
	for _, condition := range conditions {
		conditionByID[condition.ID] = condition
	}

	eventCursor, err := store.db.Collection("asset_events").Find(ctx,
		bson.M{"asset_id": bson.M{"$in": assetIDs}},
		options.Find().SetSort(bson.D{
			{Key: "asset_id", Value: 1},
			{Key: "occurred_at", Value: -1},
			{Key: "_id", Value: -1},
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil riwayat aset: %w", err)
	}
	defer eventCursor.Close(ctx)
	eventDocuments := make([]assetEventDocument, 0)
	if err := eventCursor.All(ctx, &eventDocuments); err != nil {
		return nil, fmt.Errorf("baca riwayat aset: %w", err)
	}

	actorIDs := make([]string, 0)
	seenActors := map[string]bool{}
	for _, event := range eventDocuments {
		if !seenActors[event.PerformedBy] {
			actorIDs = append(actorIDs, event.PerformedBy)
			seenActors[event.PerformedBy] = true
		}
		if event.PreviousConditionID != nil && !seenConditions[*event.PreviousConditionID] {
			conditionIDs = append(conditionIDs, *event.PreviousConditionID)
			seenConditions[*event.PreviousConditionID] = true
		}
		if event.NewConditionID != nil && !seenConditions[*event.NewConditionID] {
			conditionIDs = append(conditionIDs, *event.NewConditionID)
			seenConditions[*event.NewConditionID] = true
		}
	}
	missingConditionIDs := make([]string, 0)
	for _, id := range conditionIDs {
		if _, exists := conditionByID[id]; !exists {
			missingConditionIDs = append(missingConditionIDs, id)
		}
	}
	if len(missingConditionIDs) > 0 {
		additionalConditions := make([]inventoryConditionDocument, 0)
		if err := findInventoryDocuments(ctx, store.db.Collection("conditions"), missingConditionIDs, &additionalConditions); err != nil {
			return nil, err
		}
		for _, condition := range additionalConditions {
			conditionByID[condition.ID] = condition
		}
	}
	actors := make([]inventoryUserDocument, 0)
	if err := findInventoryDocuments(ctx, store.db.Collection("users"), actorIDs, &actors); err != nil {
		return nil, err
	}
	actorByID := make(map[string]string, len(actors))
	for _, actor := range actors {
		actorByID[actor.ID] = actor.FullName
	}
	eventsByAsset := make(map[string][]inventory.EventView, len(assets))
	for _, event := range eventDocuments {
		previousCondition := ""
		if event.PreviousConditionID != nil {
			previous, found := conditionByID[*event.PreviousConditionID]
			if !found {
				return nil, fmt.Errorf("kondisi lama %s pada riwayat aset tidak ditemukan", *event.PreviousConditionID)
			}
			previousCondition = inventoryConditionLabel(previous)
		}
		newCondition := ""
		if event.NewConditionID != nil {
			current, found := conditionByID[*event.NewConditionID]
			if !found {
				return nil, fmt.Errorf("kondisi baru %s pada riwayat aset tidak ditemukan", *event.NewConditionID)
			}
			newCondition = inventoryConditionLabel(current)
		}
		performer, found := actorByID[event.PerformedBy]
		if !found || performer == "" {
			return nil, fmt.Errorf("pelaku %s pada riwayat aset tidak ditemukan", event.PerformedBy)
		}
		eventsByAsset[event.AssetID] = append(eventsByAsset[event.AssetID], inventory.EventView{
			EventType: event.EventType, PreviousCondition: previousCondition,
			NewCondition: newCondition, PerformedBy: performer,
			Notes: event.Notes, OccurredAt: event.OccurredAt,
		})
	}

	records := make([]inventory.Record, 0, len(assets))
	for _, asset := range assets {
		item, itemFound := itemByID[asset.ItemID]
		location, locationFound := locationByID[asset.LocationID]
		condition, conditionFound := conditionByID[asset.ConditionID]
		category, categoryFound := categoryByID[item.CategoryID]
		if !itemFound || !locationFound || !conditionFound || !categoryFound {
			return nil, fmt.Errorf("referensi aset %s tidak lengkap", asset.AssetCode)
		}
		assetEvents := eventsByAsset[asset.ID]
		if assetEvents == nil {
			assetEvents = []inventory.EventView{}
		}
		records = append(records, inventory.Record{
			AssetID: asset.ID, ItemID: asset.ItemID, KindID: item.KindID, AssetCode: asset.AssetCode,
			Name: item.Name, CategoryID: item.CategoryID, Category: category.Name,
			LocationID: asset.LocationID, Location: location.Name,
			ConditionID: asset.ConditionID, Condition: inventoryConditionLabel(condition),
			CreatedAt: asset.CreatedAt, Events: assetEvents,
		})
	}
	return records, nil
}

// CATATAN PEMELIHARAAN: helper hanya melakukan lookup _id untuk batch referensi
// satu halaman; jangan gunakan untuk query yang harus memfilter status aktif.
func findInventoryDocuments[T any](ctx context.Context, collection *mongo.Collection, ids []string, output *[]T) error {
	if len(ids) == 0 {
		return nil
	}
	cursor, err := collection.Find(ctx, bson.M{"_id": bson.M{"$in": ids}})
	if err != nil {
		return fmt.Errorf("ambil data referensi inventaris: %w", err)
	}
	defer cursor.Close(ctx)
	if err := cursor.All(ctx, output); err != nil {
		return fmt.Errorf("baca data referensi inventaris: %w", err)
	}
	return nil
}

// CATATAN PEMELIHARAAN: label UI disamakan dengan pilihan kondisi; tambah code
// baru bersamaan dengan seed, parser API, filter halaman, dan tes widget.
func inventoryConditionLabel(condition inventoryConditionDocument) string {
	switch condition.Code {
	case "bagus":
		return "Bagus"
	case "perlu_perbaikan":
		return "Perlu perbaikan"
	case "dalam_service":
		return "Dalam service"
	case "rusak":
		return "Rusak"
	default:
		return condition.Name
	}
}

// CATATAN PEMELIHARAAN: referensi tidak ditemukan menjadi error validasi,
// sedangkan gangguan Mongo tetap dibungkus agar handler mengembalikan 500.
func invalidInventoryReference(err error) error {
	if errors.Is(err, mongo.ErrNoDocuments) {
		return inventory.ErrInvalidReference
	}
	return fmt.Errorf("periksa referensi inventaris: %w", err)
}

// CATATAN PEMELIHARAAN: hanya hash admin mockup lama yang cocok persis boleh
// diganti; akun admin aktif lain tidak ditimpa. Bootstrap dijalankan eksplisit
// dari terminal dan mengandalkan indeks unik serta koleksi yang sudah di-init.
func (store *Mongo) BootstrapAdmin(ctx context.Context, user users.User, legacySeedHash string) error {
	collection := store.db.Collection("users")
	result, err := collection.UpdateOne(
		ctx,
		bson.M{"username": "admin", "password_hash": legacySeedHash},
		bson.M{"$set": bson.M{
			"username":      user.Username,
			"full_name":     user.FullName,
			"password_hash": user.PasswordHash,
			"role":          "admin",
			"is_active":     true,
			"updated_at":    time.Now().UTC(),
		}},
	)
	if err != nil {
		return fmt.Errorf("perbarui akun admin demo: %w", err)
	}
	if result.MatchedCount > 0 {
		return nil
	}

	adminCount, err := collection.CountDocuments(ctx, bson.M{"role": "admin", "is_active": true})
	if err != nil {
		return fmt.Errorf("periksa admin aktif: %w", err)
	}
	if adminCount > 0 {
		return errors.New("sudah ada admin aktif; bootstrap dibatalkan")
	}
	if err := store.Create(ctx, user); err != nil {
		return err
	}
	return nil
}

// CATATAN PEMELIHARAAN: samakan ErrNotFound agar handler tidak bergantung pada
// tipe error driver Mongo; error database lain tetap dibungkus untuk log server.
func translateNotFound(err error) error {
	if errors.Is(err, mongo.ErrNoDocuments) {
		return users.ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("baca pengguna: %w", err)
	}
	return nil
}

type movementDocument struct {
	ID             string     `bson:"_id"`
	MovementNumber string     `bson:"movement_number"`
	Type           string     `bson:"movement_type"`
	Status         string     `bson:"status"`
	IdempotencyKey string     `bson:"idempotency_key"`
	PerformedBy    string     `bson:"performed_by"`
	CreatedAt      time.Time  `bson:"created_at"`
	PostedAt       *time.Time `bson:"posted_at"`
}

type movementLineDocument struct {
	ID             string  `bson:"_id"`
	MovementID     string  `bson:"movement_id"`
	LineNumber     int     `bson:"line_number"`
	ItemID         string  `bson:"item_id"`
	FromLocationID *string `bson:"from_location_id"`
	ToLocationID   *string `bson:"to_location_id"`
	Quantity       float64 `bson:"quantity"`
	Notes          string  `bson:"notes"`
}

type movementNameDocument struct {
	ID       string `bson:"_id"`
	Name     string `bson:"name"`
	FullName string `bson:"full_name"`
}

// CATATAN PEMELIHARAAN: pembacaan draft memuat header dan seluruh baris untuk
// halaman yang diminta, lalu menggabungkan nama barang/lokasi/petugas untuk
// tampilan. Ukuran halaman dibatasi handler; jika mutasi kelak multi-baris
// dalam jumlah besar, paginasi detail harus dipisah dari daftar header.
func (store *Mongo) CountMovements(ctx context.Context) (int64, error) {
	total, err := store.db.Collection("stock_movements").CountDocuments(ctx, bson.D{})
	if err != nil {
		return 0, fmt.Errorf("hitung mutasi: %w", err)
	}
	return total, nil
}

func (store *Mongo) ListMovements(ctx context.Context, skip, limit int64) ([]movements.Record, error) {
	cursor, err := store.db.Collection("stock_movements").Find(
		ctx,
		bson.D{},
		options.Find().
			SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: 1}}).
			SetSkip(skip).
			SetLimit(limit),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil halaman mutasi: %w", err)
	}
	defer cursor.Close(ctx)
	docs := make([]movementDocument, 0)
	if err := cursor.All(ctx, &docs); err != nil {
		return nil, fmt.Errorf("baca halaman mutasi: %w", err)
	}
	return store.movementRecords(ctx, docs)
}

// CATATAN PEMELIHARAAN: draft memvalidasi barang/lokasi aktif dan menyimpan
// header serta satu baris tanpa mengubah saldo. Mongo standalone tidak memberi
// transaksi lintas koleksi, sehingga kegagalan simpan baris memicu kompensasi
// penghapusan header; posting tetap harus memakai transaksi replica set.
func (store *Mongo) CreateMovement(
	ctx context.Context,
	input movements.CreateInput,
	actorID string,
	actorName string,
) (movements.Record, error) {
	if existing, err := store.findMovementByIdempotencyKey(ctx, input.IdempotencyKey); err == nil {
		record, recordErr := store.movementRecords(ctx, []movementDocument{existing})
		if recordErr != nil {
			return movements.Record{}, recordErr
		}
		if len(record) != 1 || !sameMovementRequest(record[0], input, actorID) {
			return movements.Record{}, movements.ErrConflict
		}
		return record[0], nil
	} else if !errors.Is(err, mongo.ErrNoDocuments) {
		return movements.Record{}, fmt.Errorf("periksa kunci idempotensi mutasi: %w", err)
	}

	var item movementNameDocument
	if err := store.db.Collection("items").FindOne(ctx, bson.M{
		"_id": input.Line.ItemID, "is_active": true,
	}).Decode(&item); err != nil {
		return movements.Record{}, invalidMovementReference(err)
	}
	fromName, err := store.movementLocationName(ctx, input.Line.FromLocation)
	if err != nil {
		return movements.Record{}, err
	}
	toName, err := store.movementLocationName(ctx, input.Line.ToLocation)
	if err != nil {
		return movements.Record{}, err
	}
	var actor inventoryUserDocument
	if err := store.db.Collection("users").FindOne(ctx, bson.M{"_id": actorID}).Decode(&actor); err != nil {
		return movements.Record{}, fmt.Errorf("baca petugas mutasi: %w", err)
	}

	now := time.Now().UTC()
	id := uuid.NewString()
	document := movementDocument{
		ID: id,
		MovementNumber: fmt.Sprintf(
			"MUT-%d-%s",
			now.Year(),
			strings.ToUpper(strings.ReplaceAll(id, "-", "")[:12]),
		),
		Type: input.Type, Status: "draft", IdempotencyKey: input.IdempotencyKey,
		PerformedBy: actorID, CreatedAt: now,
	}
	if _, err := store.db.Collection("stock_movements").InsertOne(ctx, bson.M{
		"_id": document.ID, "movement_number": document.MovementNumber,
		"movement_type": document.Type, "status": document.Status,
		"idempotency_key": document.IdempotencyKey, "performed_by": document.PerformedBy,
		"created_at": document.CreatedAt, "posted_at": nil,
	}); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			if existing, lookupErr := store.findMovementByIdempotencyKey(ctx, input.IdempotencyKey); lookupErr == nil {
				record, recordErr := store.movementRecords(ctx, []movementDocument{existing})
				if recordErr == nil && len(record) == 1 && sameMovementRequest(record[0], input, actorID) {
					return record[0], nil
				}
			}
			return movements.Record{}, movements.ErrConflict
		}
		return movements.Record{}, fmt.Errorf("simpan header draft mutasi: %w", err)
	}
	line := movementLineDocument{
		ID: uuid.NewString(), MovementID: id, LineNumber: 1,
		ItemID: input.Line.ItemID, FromLocationID: input.Line.FromLocation,
		ToLocationID: input.Line.ToLocation, Quantity: input.Line.Quantity,
		Notes: input.Line.Notes,
	}
	if _, err := store.db.Collection("stock_movement_lines").InsertOne(ctx, bson.M{
		"_id": line.ID, "movement_id": line.MovementID, "line_number": line.LineNumber,
		"item_id": line.ItemID, "from_location_id": line.FromLocationID,
		"to_location_id": line.ToLocationID, "quantity": line.Quantity, "notes": line.Notes,
	}); err != nil {
		cleanupContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if _, cleanupErr := store.db.Collection("stock_movements").DeleteOne(
			cleanupContext, bson.M{"_id": document.ID, "status": "draft"},
		); cleanupErr != nil {
			return movements.Record{}, fmt.Errorf(
				"simpan baris mutasi: %v; hapus header draft: %w", err, cleanupErr,
			)
		}
		return movements.Record{}, fmt.Errorf("simpan baris mutasi: %w", err)
	}
	return movements.Record{
		ID: document.ID, MovementNumber: document.MovementNumber,
		Type: document.Type, Status: document.Status,
		IdempotencyKey: document.IdempotencyKey, PerformedByID: actorID,
		PerformedBy: actor.FullName,
		CreatedAt:   now, Lines: []movements.Line{{
			LineNumber: 1, ItemID: item.ID, ItemName: item.Name,
			FromLocationID: line.FromLocationID, FromLocation: fromName,
			ToLocationID: line.ToLocationID, ToLocation: toName,
			Quantity: line.Quantity, Notes: line.Notes,
		}},
	}, nil
}

// CATATAN PEMELIHARAAN: pembatalan memakai filter status=draft agar mutasi
// yang sudah diposting atau dibatalkan tidak dapat diubah kembali. Saldo tidak
// disentuh; status dan semua data detail tetap tersimpan sebagai riwayat.
func (store *Mongo) CancelMovement(ctx context.Context, id string) (movements.Record, error) {
	result, err := store.db.Collection("stock_movements").UpdateOne(
		ctx,
		bson.M{"_id": id, "status": "draft"},
		bson.M{"$set": bson.M{"status": "cancelled"}},
	)
	if err != nil {
		return movements.Record{}, fmt.Errorf("batalkan draft mutasi: %w", err)
	}
	if result.MatchedCount == 0 {
		var current movementDocument
		if err := store.db.Collection("stock_movements").FindOne(
			ctx, bson.M{"_id": id},
		).Decode(&current); err != nil {
			if errors.Is(err, mongo.ErrNoDocuments) {
				return movements.Record{}, movements.ErrNotFound
			}
			return movements.Record{}, fmt.Errorf("periksa status mutasi: %w", err)
		}
		return movements.Record{}, movements.ErrInvalidState
	}
	var updated movementDocument
	if err := store.db.Collection("stock_movements").FindOne(
		ctx, bson.M{"_id": id},
	).Decode(&updated); err != nil {
		return movements.Record{}, fmt.Errorf("baca draft mutasi yang dibatalkan: %w", err)
	}
	records, err := store.movementRecords(ctx, []movementDocument{updated})
	if err != nil {
		return movements.Record{}, err
	}
	if len(records) != 1 {
		return movements.Record{}, errors.New("mutasi yang dibatalkan tidak menghasilkan record tampilan")
	}
	return records[0], nil
}

// CATATAN PEMELIHARAAN: posting hanya berjalan pada replica set karena satu
// mutasi mengubah saldo, status header, dan audit dalam satu transaksi. Sumber
// wajib memiliki saldo cukup; tujuan dapat membuat saldo lokasi pertamanya.
// Jika jenis barang, saldo, atau aturan mutasi berubah, sesuaikan validasi ini
// dan tes transaksi bersama validator koleksi.
func (store *Mongo) PostMovement(ctx context.Context, id, actorID string) (movements.Record, error) {
	session, err := store.client.StartSession()
	if err != nil {
		return movements.Record{}, fmt.Errorf("mulai sesi posting mutasi: %w", err)
	}
	defer session.EndSession(ctx)
	now := time.Now().UTC()
	_, err = session.WithTransaction(ctx, func(sessionContext mongo.SessionContext) (any, error) {
		var header movementDocument
		if err := store.db.Collection("stock_movements").FindOne(sessionContext, bson.M{"_id": id}).Decode(&header); err != nil {
			if errors.Is(err, mongo.ErrNoDocuments) {
				return nil, movements.ErrNotFound
			}
			return nil, fmt.Errorf("baca draft untuk posting: %w", err)
		}
		if header.Status != "draft" {
			return nil, movements.ErrInvalidState
		}
		cursor, err := store.db.Collection("stock_movement_lines").Find(sessionContext, bson.M{"movement_id": id})
		if err != nil {
			return nil, fmt.Errorf("baca baris untuk posting: %w", err)
		}
		var lines []movementLineDocument
		if err = cursor.All(sessionContext, &lines); err != nil {
			_ = cursor.Close(sessionContext)
			return nil, fmt.Errorf("baca detail untuk posting: %w", err)
		}
		_ = cursor.Close(sessionContext)
		if len(lines) == 0 {
			return nil, fmt.Errorf("draft tidak memiliki baris")
		}
		for _, line := range lines {
			var item inventoryItemDocument
			if err := store.db.Collection("items").FindOne(sessionContext, bson.M{"_id": line.ItemID, "tracking_mode": "stock", "is_active": true}).Decode(&item); err != nil {
				return nil, invalidMovementReference(err)
			}
			for _, locationID := range []*string{line.FromLocationID, line.ToLocationID} {
				if locationID == nil {
					continue
				}
				if err := store.db.Collection("locations").FindOne(sessionContext, bson.M{"_id": *locationID, "is_active": true}).Err(); err != nil {
					return nil, invalidMovementReference(err)
				}
			}
			if line.FromLocationID != nil {
				result, err := store.db.Collection("stock_balances").UpdateOne(sessionContext,
					bson.M{"item_id": line.ItemID, "location_id": *line.FromLocationID, "quantity": bson.M{"$gte": line.Quantity}},
					bson.M{"$inc": bson.M{"quantity": -line.Quantity}, "$set": bson.M{"updated_at": now}},
				)
				if err != nil {
					return nil, fmt.Errorf("kurangi saldo sumber: %w", err)
				}
				if result.MatchedCount == 0 {
					return nil, movements.ErrInsufficientStock
				}
			}
			if line.ToLocationID != nil {
				filter := bson.M{"item_id": line.ItemID, "location_id": *line.ToLocationID}
				result, err := store.db.Collection("stock_balances").UpdateOne(sessionContext, filter,
					bson.M{"$inc": bson.M{"quantity": line.Quantity}, "$set": bson.M{"updated_at": now}},
				)
				if err != nil {
					return nil, fmt.Errorf("tambah saldo tujuan: %w", err)
				}
				if result.MatchedCount == 0 {
					_, err = store.db.Collection("stock_balances").InsertOne(sessionContext, bson.M{"_id": uuid.NewString(), "item_id": line.ItemID, "location_id": *line.ToLocationID, "quantity": line.Quantity, "updated_at": now})
					if err != nil {
						return nil, fmt.Errorf("buat saldo tujuan: %w", err)
					}
				}
			}
		}
		result, err := store.db.Collection("stock_movements").UpdateOne(sessionContext,
			bson.M{"_id": id, "status": "draft"}, bson.M{"$set": bson.M{"status": "posted", "posted_at": now}},
		)
		if err != nil {
			return nil, fmt.Errorf("ubah status mutasi menjadi diposting: %w", err)
		}
		if result.MatchedCount == 0 {
			return nil, movements.ErrInvalidState
		}
		_, err = store.db.Collection("audit_logs").InsertOne(sessionContext, bson.M{
			"_id": uuid.NewString(), "actor_id": actorID, "action": "update", "entity_type": "stock_movement", "entity_id": id,
			"changes": bson.A{bson.M{"field": "status", "before": "draft", "after": "posted"}}, "occurred_at": now,
		})
		if err != nil {
			return nil, fmt.Errorf("catat audit posting mutasi: %w", err)
		}
		return nil, nil
	})
	if err != nil {
		var serverError mongo.ServerError
		if errors.As(err, &serverError) && serverError.HasErrorCode(20) {
			return movements.Record{}, movements.ErrTransactionsUnavailable
		}
		return movements.Record{}, fmt.Errorf("transaksi posting mutasi: %w", err)
	}
	var updated movementDocument
	if err := store.db.Collection("stock_movements").FindOne(ctx, bson.M{"_id": id, "status": "posted"}).Decode(&updated); err != nil {
		return movements.Record{}, fmt.Errorf("baca mutasi yang diposting: %w", err)
	}
	records, err := store.movementRecords(ctx, []movementDocument{updated})
	if err != nil {
		return movements.Record{}, err
	}
	if len(records) != 1 {
		return movements.Record{}, errors.New("mutasi yang diposting tidak menghasilkan record tampilan")
	}
	return records[0], nil
}

func (store *Mongo) findMovementByIdempotencyKey(
	ctx context.Context,
	key string,
) (movementDocument, error) {
	var result movementDocument
	err := store.db.Collection("stock_movements").FindOne(
		ctx, bson.M{"idempotency_key": key},
	).Decode(&result)
	return result, err
}

func sameMovementRequest(record movements.Record, input movements.CreateInput, actorID string) bool {
	if record.IdempotencyKey != input.IdempotencyKey ||
		record.Type != input.Type ||
		record.Status != "draft" ||
		len(record.Lines) != 1 {
		return false
	}
	line := record.Lines[0]
	return line.ItemID == input.Line.ItemID &&
		sameOptionalID(line.FromLocationID, input.Line.FromLocation) &&
		sameOptionalID(line.ToLocationID, input.Line.ToLocation) &&
		line.Quantity == input.Line.Quantity &&
		line.Notes == input.Line.Notes &&
		record.PerformedByID == actorID
}

func sameOptionalID(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func (store *Mongo) movementLocationName(ctx context.Context, id *string) (*string, error) {
	if id == nil {
		return nil, nil
	}
	var location movementNameDocument
	if err := store.db.Collection("locations").FindOne(ctx, bson.M{
		"_id": *id, "is_active": true,
	}).Decode(&location); err != nil {
		return nil, invalidMovementReference(err)
	}
	return &location.Name, nil
}

func invalidMovementReference(err error) error {
	if errors.Is(err, mongo.ErrNoDocuments) {
		return movements.ErrInvalidTarget
	}
	return fmt.Errorf("periksa referensi mutasi: %w", err)
}

func (store *Mongo) movementRecords(
	ctx context.Context,
	docs []movementDocument,
) ([]movements.Record, error) {
	if len(docs) == 0 {
		return []movements.Record{}, nil
	}
	movementIDs := make([]string, 0, len(docs))
	actorIDs := make([]string, 0, len(docs))
	for _, doc := range docs {
		movementIDs = append(movementIDs, doc.ID)
		actorIDs = append(actorIDs, doc.PerformedBy)
	}
	cursor, err := store.db.Collection("stock_movement_lines").Find(
		ctx,
		bson.M{"movement_id": bson.M{"$in": movementIDs}},
		options.Find().SetSort(bson.D{
			{Key: "movement_id", Value: 1}, {Key: "line_number", Value: 1},
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil baris mutasi: %w", err)
	}
	defer cursor.Close(ctx)
	lines := make([]movementLineDocument, 0)
	if err := cursor.All(ctx, &lines); err != nil {
		return nil, fmt.Errorf("baca baris mutasi: %w", err)
	}

	itemIDs := make([]string, 0, len(lines))
	locationIDs := make([]string, 0, len(lines)*2)
	seenItems := make(map[string]bool)
	seenLocations := make(map[string]bool)
	linesByMovement := make(map[string][]movementLineDocument, len(docs))
	for _, line := range lines {
		linesByMovement[line.MovementID] = append(linesByMovement[line.MovementID], line)
		if !seenItems[line.ItemID] {
			itemIDs = append(itemIDs, line.ItemID)
			seenItems[line.ItemID] = true
		}
		for _, locationID := range []*string{line.FromLocationID, line.ToLocationID} {
			if locationID != nil && !seenLocations[*locationID] {
				locationIDs = append(locationIDs, *locationID)
				seenLocations[*locationID] = true
			}
		}
	}
	itemNames, err := store.movementNames(ctx, "items", itemIDs)
	if err != nil {
		return nil, err
	}
	locationNames, err := store.movementNames(ctx, "locations", locationIDs)
	if err != nil {
		return nil, err
	}
	actorNames, err := store.movementNames(ctx, "users", actorIDs)
	if err != nil {
		return nil, err
	}
	result := make([]movements.Record, 0, len(docs))
	for _, doc := range docs {
		lineDocs := linesByMovement[doc.ID]
		if len(lineDocs) == 0 {
			return nil, fmt.Errorf("mutasi %s tidak memiliki baris", doc.ID)
		}
		record := movements.Record{
			ID: doc.ID, MovementNumber: doc.MovementNumber,
			Type: doc.Type, Status: doc.Status, IdempotencyKey: doc.IdempotencyKey,
			PerformedByID: doc.PerformedBy, PerformedBy: actorNames[doc.PerformedBy],
			CreatedAt: doc.CreatedAt,
			PostedAt:  doc.PostedAt, Lines: make([]movements.Line, 0, len(lineDocs)),
		}
		if record.PerformedBy == "" {
			return nil, fmt.Errorf("petugas mutasi %s tidak ditemukan", doc.ID)
		}
		for _, line := range lineDocs {
			itemName := itemNames[line.ItemID]
			if itemName == "" {
				return nil, fmt.Errorf("barang %s pada mutasi %s tidak ditemukan", line.ItemID, doc.ID)
			}
			fromName, err := movementOptionalName(locationNames, line.FromLocationID)
			if err != nil {
				return nil, fmt.Errorf("lokasi asal mutasi %s: %w", doc.ID, err)
			}
			toName, err := movementOptionalName(locationNames, line.ToLocationID)
			if err != nil {
				return nil, fmt.Errorf("lokasi tujuan mutasi %s: %w", doc.ID, err)
			}
			record.Lines = append(record.Lines, movements.Line{
				LineNumber: line.LineNumber, ItemID: line.ItemID, ItemName: itemName,
				FromLocationID: line.FromLocationID, FromLocation: fromName,
				ToLocationID: line.ToLocationID, ToLocation: toName,
				Quantity: line.Quantity, Notes: line.Notes,
			})
		}
		result = append(result, record)
	}
	return result, nil
}

func (store *Mongo) movementNames(ctx context.Context, collection string, ids []string) (map[string]string, error) {
	result := make(map[string]string, len(ids))
	if len(ids) == 0 {
		return result, nil
	}
	cursor, err := store.db.Collection(collection).Find(
		ctx, bson.M{"_id": bson.M{"$in": ids}},
		options.Find().SetProjection(bson.M{"_id": 1, "name": 1, "full_name": 1}),
	)
	if err != nil {
		return nil, fmt.Errorf("ambil nama referensi mutasi: %w", err)
	}
	defer cursor.Close(ctx)
	var names []movementNameDocument
	if err := cursor.All(ctx, &names); err != nil {
		return nil, fmt.Errorf("baca nama referensi mutasi: %w", err)
	}
	for _, name := range names {
		if collection == "users" {
			result[name.ID] = name.FullName
		} else {
			result[name.ID] = name.Name
		}
	}
	return result, nil
}

func movementOptionalName(names map[string]string, id *string) (*string, error) {
	if id == nil {
		return nil, nil
	}
	name, found := names[*id]
	if !found {
		return nil, errors.New("referensi tidak ditemukan")
	}
	return &name, nil
}
