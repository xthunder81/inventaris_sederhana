package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"inventaris_sederhana/backend/internal/auth"
	"inventaris_sederhana/backend/internal/inventory"
	"inventaris_sederhana/backend/internal/locations"
	"inventaris_sederhana/backend/internal/maintenance"
	"inventaris_sederhana/backend/internal/masterdata"
	"inventaris_sederhana/backend/internal/movements"
	"inventaris_sederhana/backend/internal/users"
)

type memoryStore struct {
	user               users.User
	events             []users.LoginEvent
	locations          []locations.Location
	kinds              []masterdata.ItemKind
	categories         []masterdata.Category
	assets             []inventory.Record
	stockItems         []inventory.StockItem
	movements          []movements.Record
	maintenanceRecords []maintenance.Record
}

// CATATAN PEMELIHARAAN: fake store mempertahankan satu akun agar tes HTTP
// memverifikasi kontrak handler tanpa menulis ke MongoDB pengembang.
func (store *memoryStore) FindByUsername(_ context.Context, username string) (users.User, error) {
	if username != store.user.Username {
		return users.User{}, users.ErrNotFound
	}
	return store.user, nil
}

// CATATAN PEMELIHARAAN: pencarian ID memakai record yang sama agar middleware
// dapat menguji perubahan status/peran terbaru dalam memori.
func (store *memoryStore) FindByID(_ context.Context, id string) (users.User, error) {
	if id != store.user.ID {
		return users.User{}, users.ErrNotFound
	}
	return store.user, nil
}

// CATATAN PEMELIHARAAN: List memberi data minimal untuk jalur admin; bila
// pagination/filter handler berubah, fake ini perlu merepresentasikan batasnya.
func (store *memoryStore) List(context.Context, int64, int64) ([]users.User, error) {
	return []users.User{store.user}, nil
}

// CATATAN PEMELIHARAAN: satu akun cukup untuk menguji metadata pagination,
// bukan untuk mengetes performa query atau urutan MongoDB.
func (store *memoryStore) Count(context.Context) (int64, error) {
	return 1, nil
}

// CATATAN PEMELIHARAAN: penyimpanan in-memory dipakai hanya oleh tes; efek
// persistensi produksi tetap harus diverifikasi pada adapter Mongo.
func (store *memoryStore) Create(_ context.Context, user users.User) error {
	store.user = user
	return nil
}

// CATATAN PEMELIHARAAN: terapkan field pointer sama seperti PATCH agar tes
// dapat menangkap perbedaan nilai tidak dikirim dan nilai false/kosong.
func (store *memoryStore) Update(_ context.Context, _ string, update users.Update) (users.User, error) {
	if update.Username != nil {
		store.user.Username = *update.Username
	}
	if update.Role != nil {
		store.user.Role = *update.Role
	}
	if update.IsActive != nil {
		store.user.IsActive = *update.IsActive
	}
	if update.FullName != nil {
		store.user.FullName = *update.FullName
	}
	return store.user, nil
}

// CATATAN PEMELIHARAAN: fake mengganti hash di memori; tes handler perlu
// memeriksa bahwa nilai yang diberikan sudah hash, bukan plaintext.
func (store *memoryStore) UpdatePassword(_ context.Context, _ string, passwordHash string) error {
	store.user.PasswordHash = passwordHash
	return nil
}

// CATATAN PEMELIHARAAN: pembaruan mengubah waktu login pada record fake supaya
// response/authorization memakai state terkini sebagaimana Mongo adapter.
func (store *memoryStore) UpdateLastLogin(_ context.Context, _ string, at time.Time) error {
	store.user.LastLoginAt = &at
	store.user.UpdatedAt = &at
	return nil
}

// CATATAN PEMELIHARAAN: event disimpan untuk assertion keberhasilan login;
// jangan memperluas fixture ini dengan password atau bearer token.
func (store *memoryStore) RecordLogin(_ context.Context, event users.LoginEvent) error {
	store.events = append(store.events, event)
	return nil
}

func (store *memoryStore) ListLocations(context.Context) ([]locations.Location, error) {
	result := make([]locations.Location, len(store.locations))
	copy(result, store.locations)
	return result, nil
}

func (store *memoryStore) CreateLocation(_ context.Context, location locations.Location) error {
	for _, current := range store.locations {
		if strings.EqualFold(current.Code, location.Code) {
			return locations.ErrConflict
		}
	}
	store.locations = append(store.locations, location)
	return nil
}

func (store *memoryStore) UpdateLocation(_ context.Context, id string, location locations.Location) (locations.Location, error) {
	for index, current := range store.locations {
		if current.ID != id && strings.EqualFold(current.Code, location.Code) {
			return locations.Location{}, locations.ErrConflict
		}
		if current.ID == id {
			store.locations[index] = location
			return location, nil
		}
	}
	return locations.Location{}, locations.ErrNotFound
}

func (store *memoryStore) ListItemKinds(context.Context) ([]masterdata.ItemKind, error) {
	result := make([]masterdata.ItemKind, len(store.kinds))
	copy(result, store.kinds)
	return result, nil
}

func (store *memoryStore) CreateItemKind(_ context.Context, item masterdata.ItemKind) error {
	for _, current := range store.kinds {
		if strings.EqualFold(current.Code, item.Code) {
			return masterdata.ErrConflict
		}
	}
	store.kinds = append(store.kinds, item)
	return nil
}

func (store *memoryStore) UpdateItemKind(_ context.Context, id string, item masterdata.ItemKind) (masterdata.ItemKind, error) {
	for index, current := range store.kinds {
		if current.ID != id && strings.EqualFold(current.Code, item.Code) {
			return masterdata.ItemKind{}, masterdata.ErrConflict
		}
		if current.ID == id {
			store.kinds[index] = item
			return item, nil
		}
	}
	return masterdata.ItemKind{}, masterdata.ErrNotFound
}

func (store *memoryStore) ListCategories(context.Context) ([]masterdata.Category, error) {
	result := make([]masterdata.Category, len(store.categories))
	copy(result, store.categories)
	return result, nil
}

func (store *memoryStore) CreateCategory(_ context.Context, item masterdata.Category) error {
	for _, current := range store.categories {
		if strings.EqualFold(current.Code, item.Code) {
			return masterdata.ErrConflict
		}
	}
	store.categories = append(store.categories, item)
	return nil
}

func (store *memoryStore) UpdateCategory(_ context.Context, id string, item masterdata.Category) (masterdata.Category, error) {
	for index, current := range store.categories {
		if current.ID != id && strings.EqualFold(current.Code, item.Code) {
			return masterdata.Category{}, masterdata.ErrConflict
		}
		if current.ID == id {
			store.categories[index] = item
			return item, nil
		}
	}
	return masterdata.Category{}, masterdata.ErrNotFound
}

// CATATAN PEMELIHARAAN: ping sukses memungkinkan tes health/handler tanpa
// koneksi eksternal; kegagalan DB perlu dites dengan fake terpisah bila alurnya
// berubah.
func (store *memoryStore) Ping(context.Context) error {
	return nil
}

func (store *memoryStore) CountAssets(context.Context) (int64, error) {
	return int64(len(store.assets)), nil
}

func (store *memoryStore) ListAssets(_ context.Context, skip, limit int64) ([]inventory.Record, error) {
	if skip >= int64(len(store.assets)) {
		return []inventory.Record{}, nil
	}
	end := skip + limit
	if end > int64(len(store.assets)) {
		end = int64(len(store.assets))
	}
	result := append([]inventory.Record(nil), store.assets[skip:end]...)
	return result, nil
}

func (store *memoryStore) CreateAsset(
	_ context.Context,
	input inventory.CreateInput,
	_ string,
	actorName string,
) (inventory.Record, error) {
	condition := testConditionLabel(input.ConditionCode)
	record := inventory.Record{
		AssetID:   "8a000001-0000-4000-8000-000000000001",
		ItemID:    "8a000002-0000-4000-8000-000000000002",
		KindID:    input.KindID,
		AssetCode: "AST-TEST-0001", Name: input.Name,
		CategoryID: input.CategoryID, Category: "Elektronik",
		LocationID: input.LocationID, Location: "Ruang Uji",
		ConditionID: "8a000003-0000-4000-8000-000000000003",
		Condition:   condition, CreatedAt: time.Now().UTC(),
		Events: []inventory.EventView{{
			EventType: "received", NewCondition: condition,
			PerformedBy: actorName, Notes: "Aset didaftarkan.",
			OccurredAt: time.Now().UTC(),
		}},
	}
	store.assets = append([]inventory.Record{record}, store.assets...)
	return record, nil
}

func (store *memoryStore) ChangeAssetCondition(
	_ context.Context,
	assetID, conditionCode, notes, _, actorName string,
) (inventory.Record, error) {
	for index, asset := range store.assets {
		if asset.AssetID != assetID {
			continue
		}
		condition := testConditionLabel(conditionCode)
		if asset.Condition == condition {
			return inventory.Record{}, inventory.ErrConditionSame
		}
		event := inventory.EventView{
			EventType: "condition_changed", PreviousCondition: asset.Condition,
			NewCondition: condition, PerformedBy: actorName,
			Notes: notes, OccurredAt: time.Now().UTC(),
		}
		asset.Condition = condition
		asset.Events = append([]inventory.EventView{event}, asset.Events...)
		store.assets[index] = asset
		return asset, nil
	}
	return inventory.Record{}, inventory.ErrNotFound
}

func (store *memoryStore) UpdateAsset(_ context.Context, id string, input inventory.UpdateInput, _, actorName string) (inventory.Record, error) {
	for index, asset := range store.assets {
		if asset.AssetID != id {
			continue
		}
		asset.Name, asset.CategoryID, asset.LocationID = input.Name, input.CategoryID, input.LocationID
		asset.KindID = input.KindID
		asset.Condition = testConditionLabel(input.ConditionCode)
		asset.Events = append([]inventory.EventView{{EventType: "asset_edited", NewCondition: asset.Condition, PerformedBy: actorName, Notes: "Data aset diperbarui.", OccurredAt: time.Now().UTC()}}, asset.Events...)
		store.assets[index] = asset
		return asset, nil
	}
	return inventory.Record{}, inventory.ErrNotFound
}

func (store *memoryStore) ArchiveAsset(_ context.Context, id, _, _ string) error {
	for index, asset := range store.assets {
		if asset.AssetID == id {
			store.assets = append(store.assets[:index], store.assets[index+1:]...)
			return nil
		}
	}
	return inventory.ErrNotFound
}

func (store *memoryStore) ListStockItems(context.Context) ([]inventory.StockItem, error) {
	return append([]inventory.StockItem(nil), store.stockItems...), nil
}

func (store *memoryStore) CreateStockItem(_ context.Context, input inventory.StockItemInput) (inventory.StockItem, error) {
	if input.Name == "" || input.Unit == "" || input.InitialQuantity < 0 {
		return inventory.StockItem{}, inventory.ErrInvalidReference
	}
	item := inventory.StockItem{ItemID: "8a000004-0000-4000-8000-000000000004", Code: "STK-TEST-0001", Name: input.Name, KindID: input.KindID, CategoryID: input.CategoryID, Category: "Alat Tulis Kantor", Unit: input.Unit, MinimumStock: input.MinimumStock, Balances: []inventory.StockBalance{{LocationID: input.LocationID, Location: "Ruang Uji", Quantity: input.InitialQuantity, UpdatedAt: time.Now().UTC()}}}
	store.stockItems = append(store.stockItems, item)
	return item, nil
}

func (store *memoryStore) UpdateStockItem(_ context.Context, id string, input inventory.StockItemUpdateInput, _ string) (inventory.StockItem, error) {
	for index, item := range store.stockItems {
		if item.ItemID != id {
			continue
		}
		item.Name = input.Name
		item.CategoryID = input.CategoryID
		item.Unit = input.Unit
		item.MinimumStock = input.MinimumStock
		for balanceIndex, balance := range item.Balances {
			if balance.LocationID == input.LocationID {
				item.Balances[balanceIndex].Quantity = input.Quantity
			}
		}
		store.stockItems[index] = item
		return item, nil
	}
	return inventory.StockItem{}, inventory.ErrNotFound
}

func testConditionLabel(code string) string {
	switch code {
	case "bagus":
		return "Bagus"
	case "perlu_perbaikan":
		return "Perlu perbaikan"
	case "dalam_service":
		return "Dalam service"
	case "rusak":
		return "Rusak"
	default:
		return code
	}
}

func (store *memoryStore) CountMovements(context.Context) (int64, error) {
	return int64(len(store.movements)), nil
}

func (store *memoryStore) ListMovements(_ context.Context, skip, limit int64) ([]movements.Record, error) {
	if skip >= int64(len(store.movements)) {
		return []movements.Record{}, nil
	}
	end := skip + limit
	if end > int64(len(store.movements)) {
		end = int64(len(store.movements))
	}
	return append([]movements.Record(nil), store.movements[skip:end]...), nil
}

func (store *memoryStore) CreateMovement(
	_ context.Context,
	input movements.CreateInput,
	actorID string,
	actorName string,
) (movements.Record, error) {
	for _, current := range store.movements {
		if current.IdempotencyKey == input.IdempotencyKey {
			if current.Type == input.Type && len(current.Lines) == 1 {
				line := current.Lines[0]
				if line.ItemID == input.Line.ItemID &&
					sameMovementLocationID(line.FromLocationID, input.Line.FromLocation) &&
					sameMovementLocationID(line.ToLocationID, input.Line.ToLocation) &&
					line.Quantity == input.Line.Quantity && line.Notes == input.Line.Notes &&
					current.PerformedByID == actorID {
					return current, nil
				}
			}
			return movements.Record{}, movements.ErrConflict
		}
	}
	now := time.Now().UTC()
	id := "8a000010-0000-4000-8000-000000000010"
	record := movements.Record{
		ID: id, MovementNumber: "MUT-2026-TEST0001",
		Type: input.Type, Status: "draft", IdempotencyKey: input.IdempotencyKey,
		PerformedByID: actorID, PerformedBy: actorName, CreatedAt: now,
		Lines: []movements.Line{{
			LineNumber: 1, ItemID: input.Line.ItemID, ItemName: "Barang uji",
			FromLocationID: input.Line.FromLocation, ToLocationID: input.Line.ToLocation,
			Quantity: input.Line.Quantity, Notes: input.Line.Notes,
		}},
	}
	store.movements = append([]movements.Record{record}, store.movements...)
	return record, nil
}

func (store *memoryStore) CancelMovement(_ context.Context, id string) (movements.Record, error) {
	for index, current := range store.movements {
		if current.ID != id {
			continue
		}
		if current.Status != "draft" {
			return movements.Record{}, movements.ErrInvalidState
		}
		current.Status = "cancelled"
		store.movements[index] = current
		return current, nil
	}
	return movements.Record{}, movements.ErrNotFound
}

func (store *memoryStore) PostMovement(_ context.Context, id, _ string) (movements.Record, error) {
	for index, current := range store.movements {
		if current.ID != id {
			continue
		}
		if current.Status != "draft" {
			return movements.Record{}, movements.ErrInvalidState
		}
		now := time.Now().UTC()
		current.Status, current.PostedAt = "posted", &now
		store.movements[index] = current
		return current, nil
	}
	return movements.Record{}, movements.ErrNotFound
}

func (store *memoryStore) CountMaintenance(context.Context) (int64, error) {
	return int64(len(store.maintenanceRecords)), nil
}

func (store *memoryStore) ListMaintenance(_ context.Context, skip, limit int64) ([]maintenance.Record, error) {
	if skip >= int64(len(store.maintenanceRecords)) {
		return []maintenance.Record{}, nil
	}
	end := skip + limit
	if end > int64(len(store.maintenanceRecords)) {
		end = int64(len(store.maintenanceRecords))
	}
	return append([]maintenance.Record(nil), store.maintenanceRecords[skip:end]...), nil
}

func (store *memoryStore) CreateMaintenance(_ context.Context, input maintenance.CreateInput, actorID string) (maintenance.Record, error) {
	record := maintenance.Record{ID: "8a000020-0000-4000-8000-000000000020", AssetID: input.AssetID, AssetCode: "AST-TEST", AssetName: "Aset Uji", ReportedBy: store.user.FullName, ReportedByID: actorID, Status: "reported", Description: input.Description, ReportedAt: time.Now().UTC()}
	store.maintenanceRecords = append([]maintenance.Record{record}, store.maintenanceRecords...)
	return record, nil
}

func (store *memoryStore) UpdateMaintenance(_ context.Context, id string, input maintenance.UpdateInput) (maintenance.Record, error) {
	for index, current := range store.maintenanceRecords {
		if current.ID != id {
			continue
		}
		if !maintenance.CanTransition(current.Status, input.Status) {
			return maintenance.Record{}, maintenance.ErrInvalidState
		}
		current.Status = input.Status
		if input.Status == "completed" {
			current.Cost = input.Cost
		}
		if input.Status == "completed" || input.Status == "cancelled" {
			now := time.Now().UTC()
			current.ClosedAt = &now
		}
		store.maintenanceRecords[index] = current
		return current, nil
	}
	return maintenance.Record{}, maintenance.ErrNotFound
}

func sameMovementLocationID(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

// CATATAN PEMELIHARAAN: kontrak ini menjaga field create server-owned,
// validasi transisi, dan izin baca/tulis tanpa memerlukan MongoDB.
func TestMaintenanceEndpointsPersistReportAndTransitions(t *testing.T) {
	store := &memoryStore{user: users.User{
		ID: "96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40", Username: "petugas",
		FullName: "Petugas Uji", Role: "petugas", IsActive: true,
	}}
	api, err := New(store, store, []byte("0123456789abcdef0123456789abcdef"), nil, log.New(io.Discard, "", 0))
	if err != nil {
		t.Fatal(err)
	}
	token, _, err := api.tokens.Issue(store.user.ID, store.user.Role)
	if err != nil {
		t.Fatal(err)
	}
	handler := api.Handler()
	request := func(method, path, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		if body != "" {
			req.Header.Set("Content-Type", "application/json")
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, req)
		return response
	}
	const assetID = "8a000021-0000-4000-8000-000000000021"
	created := request(http.MethodPost, "/api/v1/maintenance-records", `{"asset_id":"`+assetID+`","description":"Layar tidak menyala"}`)
	var record maintenance.Record
	if created.Code != http.StatusCreated || json.Unmarshal(created.Body.Bytes(), &record) != nil || record.Status != "reported" || record.ReportedBy != "Petugas Uji" {
		t.Fatalf("laporan baru harus menyimpan status dan pelapor server, status=%d body=%s", created.Code, created.Body)
	}
	started := request(http.MethodPatch, "/api/v1/maintenance-records/"+record.ID, `{"status":"in_progress","cost":0}`)
	if started.Code != http.StatusOK || !strings.Contains(started.Body.String(), `"status":"in_progress"`) {
		t.Fatalf("laporan harus dapat dimulai, status=%d body=%s", started.Code, started.Body)
	}
	completed := request(http.MethodPatch, "/api/v1/maintenance-records/"+record.ID, `{"status":"completed","cost":125000}`)
	if completed.Code != http.StatusOK || !strings.Contains(completed.Body.String(), `"cost":125000`) {
		t.Fatalf("laporan harus dapat diselesaikan dengan biaya akhir, status=%d body=%s", completed.Code, completed.Body)
	}
	invalidTransition := request(http.MethodPatch, "/api/v1/maintenance-records/"+record.ID, `{"status":"cancelled","cost":0}`)
	if invalidTransition.Code != http.StatusConflict {
		t.Fatalf("laporan selesai harus terminal, status=%d", invalidTransition.Code)
	}
	listed := request(http.MethodGet, "/api/v1/maintenance-records?page=1&page_size=10", "")
	if listed.Code != http.StatusOK || !strings.Contains(listed.Body.String(), `"total":1`) {
		t.Fatalf("laporan harus tampil di daftar, status=%d body=%s", listed.Code, listed.Body)
	}
}

// CATATAN PEMELIHARAAN: tes ini menjaga response bebas hash serta memastikan
// perubahan peran/nonaktif di DB langsung mencabut izin token yang diterbitkan.
func TestLoginOmitsPasswordHashAndAuthorizationUsesCurrentAccount(t *testing.T) {
	password := "kata-sandi-rahasia-yang-kuat"
	passwordHash, err := auth.HashPassword(password)
	if err != nil {
		t.Fatal(err)
	}
	store := &memoryStore{user: users.User{
		ID:           "96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		Username:     "admin",
		FullName:     "Admin Sekolah",
		PasswordHash: passwordHash,
		Role:         "admin",
		IsActive:     true,
		CreatedAt:    time.Now().UTC(),
	}}
	api, err := New(
		store,
		store,
		[]byte("0123456789abcdef0123456789abcdef"),
		nil,
		log.New(io.Discard, "", 0),
	)
	if err != nil {
		t.Fatal(err)
	}
	handler := api.Handler()

	loginRequest := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/auth/login",
		strings.NewReader(`{"username":" ADMIN ","password":"`+password+`"}`),
	)
	loginRequest.Header.Set("Content-Type", "application/json")
	loginResponse := httptest.NewRecorder()
	handler.ServeHTTP(loginResponse, loginRequest)
	if loginResponse.Code != http.StatusOK {
		t.Fatalf("login status = %d, want %d: %s", loginResponse.Code, http.StatusOK, loginResponse.Body)
	}
	var loginBody struct {
		AccessToken string         `json:"access_token"`
		User        map[string]any `json:"user"`
	}
	if err := json.Unmarshal(loginResponse.Body.Bytes(), &loginBody); err != nil {
		t.Fatal(err)
	}
	if loginBody.AccessToken == "" {
		t.Fatal("login harus mengembalikan token")
	}
	if _, containsHash := loginBody.User["password_hash"]; containsHash {
		t.Fatal("response login tidak boleh mengirim hash kata sandi")
	}
	if len(store.events) != 1 || store.events[0].Result != "success" {
		t.Fatalf("login berhasil harus dicatat: %#v", store.events)
	}

	usersRequest := httptest.NewRequest(http.MethodGet, "/api/v1/users", nil)
	usersRequest.Header.Set("Authorization", "Bearer "+loginBody.AccessToken)
	usersResponse := httptest.NewRecorder()
	handler.ServeHTTP(usersResponse, usersRequest)
	if usersResponse.Code != http.StatusOK {
		t.Fatalf("admin aktif harus dapat membaca pengguna, status=%d", usersResponse.Code)
	}

	updateRequest := httptest.NewRequest(
		http.MethodPatch,
		"/api/v1/users/"+store.user.ID,
		strings.NewReader(`{"username":" Operator.One "}`),
	)
	updateRequest.Header.Set("Authorization", "Bearer "+loginBody.AccessToken)
	updateRequest.Header.Set("Content-Type", "application/json")
	updateResponse := httptest.NewRecorder()
	handler.ServeHTTP(updateResponse, updateRequest)
	if updateResponse.Code != http.StatusOK || store.user.Username != "operator.one" {
		t.Fatalf("username harus dinormalisasi; status=%d username=%q", updateResponse.Code, store.user.Username)
	}

	store.user.Role = "petugas"
	demotedResponse := httptest.NewRecorder()
	handler.ServeHTTP(demotedResponse, usersRequest)
	if demotedResponse.Code != http.StatusForbidden {
		t.Fatalf("peran yang sudah dicabut harus ditolak, status=%d", demotedResponse.Code)
	}

	store.user.IsActive = false
	profileRequest := httptest.NewRequest(http.MethodGet, "/api/v1/auth/me", nil)
	profileRequest.Header.Set("Authorization", "Bearer "+loginBody.AccessToken)
	profileResponse := httptest.NewRecorder()
	handler.ServeHTTP(profileResponse, profileRequest)
	if profileResponse.Code != http.StatusUnauthorized {
		t.Fatalf("akun yang dinonaktifkan harus ditolak, status=%d", profileResponse.Code)
	}
}

// CATATAN PEMELIHARAAN: decoder harus menolak field ekstra agar perubahan
// kontrak API disengaja dan field sensitif tidak lolos sebagai input tak dikenal.
func TestJSONDecoderRejectsUnknownFields(t *testing.T) {
	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/auth/login",
		bytes.NewBufferString(`{"username":"admin","password":"x","is_admin":true}`),
	)
	response := httptest.NewRecorder()
	var input loginRequest
	if decodeJSON(response, request, &input) {
		t.Fatal("field tak dikenal harus ditolak")
	}
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadRequest)
	}
}

// CATATAN PEMELIHARAAN: tes ini mengunci izin baca semua role, tulis hanya
// Admin, dan aturan hierarki yang juga harus diterapkan klien sebagai UX saja.
func TestLocationEndpointsValidateHierarchyAndRole(t *testing.T) {
	store := &memoryStore{user: users.User{
		ID:       "96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		Username: "admin",
		FullName: "Admin Sekolah",
		Role:     "admin",
		IsActive: true,
	}}
	api, err := New(
		store,
		store,
		[]byte("0123456789abcdef0123456789abcdef"),
		nil,
		log.New(io.Discard, "", 0),
	)
	if err != nil {
		t.Fatal(err)
	}

	token, _, err := api.tokens.Issue(store.user.ID, store.user.Role)
	if err != nil {
		t.Fatal(err)
	}
	handler := api.Handler()
	request := func(method, path, body string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(method, path, strings.NewReader(body))
		request.Header.Set("Authorization", "Bearer "+token)
		if body != "" {
			request.Header.Set("Content-Type", "application/json")
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}

	emptyList := request(http.MethodGet, "/api/v1/locations", "")
	var emptyPayload struct {
		Data  []locations.Location `json:"data"`
		Total int                  `json:"total"`
	}
	if err := json.Unmarshal(emptyList.Body.Bytes(), &emptyPayload); err != nil {
		t.Fatal(err)
	}
	if emptyList.Code != http.StatusOK || emptyPayload.Data == nil || emptyPayload.Total != 0 {
		t.Fatalf("daftar kosong harus berupa array JSON, status=%d body=%s", emptyList.Code, emptyList.Body)
	}

	createdRoot := request(http.MethodPost, "/api/v1/locations", `{
		"code":" sek-001 ","name":"SMP Negeri 1","location_type":"sekolah","parent_id":null
	}`)
	if createdRoot.Code != http.StatusCreated {
		t.Fatalf("buat lokasi utama status=%d body=%s", createdRoot.Code, createdRoot.Body)
	}
	var root locations.Location
	if err := json.Unmarshal(createdRoot.Body.Bytes(), &root); err != nil {
		t.Fatal(err)
	}
	if root.Code != "SEK-001" || root.ParentID != nil || !root.IsActive {
		t.Fatalf("lokasi utama tidak dinormalisasi/default aktif: %#v", root)
	}

	childBody, err := json.Marshal(map[string]any{
		"code":          "RNG-001",
		"name":          "Ruang Tata Usaha",
		"location_type": "ruang",
		"parent_id":     root.ID,
		"is_active":     true,
	})
	if err != nil {
		t.Fatal(err)
	}
	createdChild := request(http.MethodPost, "/api/v1/locations", string(childBody))
	if createdChild.Code != http.StatusCreated {
		t.Fatalf("buat lokasi turunan status=%d body=%s", createdChild.Code, createdChild.Body)
	}
	var child locations.Location
	if err := json.Unmarshal(createdChild.Body.Bytes(), &child); err != nil {
		t.Fatal(err)
	}

	duplicate := request(http.MethodPost, "/api/v1/locations", `{
		"code":"sek-001","name":"Duplikat","location_type":"sekolah"
	}`)
	if duplicate.Code != http.StatusConflict {
		t.Fatalf("kode duplikat harus konflik, status=%d", duplicate.Code)
	}

	cycleBody, _ := json.Marshal(map[string]any{"parent_id": child.ID})
	cycle := request(http.MethodPatch, "/api/v1/locations/"+root.ID, string(cycleBody))
	if cycle.Code != http.StatusConflict {
		t.Fatalf("siklus induk-anak harus ditolak, status=%d body=%s", cycle.Code, cycle.Body)
	}

	archiveBody := `{"is_active":false}`
	archiveParent := request(http.MethodPatch, "/api/v1/locations/"+root.ID, archiveBody)
	if archiveParent.Code != http.StatusConflict {
		t.Fatalf("induk dengan turunan aktif tidak boleh diarsipkan, status=%d", archiveParent.Code)
	}

	store.user.Role = "petugas"
	list := request(http.MethodGet, "/api/v1/locations", "")
	if list.Code != http.StatusOK {
		t.Fatalf("petugas yang terautentikasi boleh membaca lokasi, status=%d", list.Code)
	}
	createForbidden := request(http.MethodPost, "/api/v1/locations", `{
		"code":"GDG-001","name":"Gudang","location_type":"gudang"
	}`)
	if createForbidden.Code != http.StatusForbidden {
		t.Fatalf("petugas tidak boleh mengubah lokasi, status=%d", createForbidden.Code)
	}
}

// CATATAN PEMELIHARAAN: tes mengunci pemisahan koleksi, normalisasi/unik kode,
// validasi panjang deskripsi, status arsip, dan otorisasi master katalog.
func TestCatalogEndpointsValidateFieldsAndRole(t *testing.T) {
	store := &memoryStore{user: users.User{
		ID:       "96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		Username: "admin",
		FullName: "Admin Sekolah",
		Role:     "admin",
		IsActive: true,
	}}
	api, err := New(
		store,
		store,
		[]byte("0123456789abcdef0123456789abcdef"),
		nil,
		log.New(io.Discard, "", 0),
	)
	if err != nil {
		t.Fatal(err)
	}

	token, _, err := api.tokens.Issue(store.user.ID, store.user.Role)
	if err != nil {
		t.Fatal(err)
	}
	handler := api.Handler()
	request := func(method, path, body string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(method, path, strings.NewReader(body))
		request.Header.Set("Authorization", "Bearer "+token)
		if body != "" {
			request.Header.Set("Content-Type", "application/json")
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}

	createdKind := request(http.MethodPost, "/api/v1/item-kinds", `{
		"code":" aset-tetap ","name":" Aset Tetap "
	}`)
	if createdKind.Code != http.StatusCreated {
		t.Fatalf("buat jenis barang status=%d body=%s", createdKind.Code, createdKind.Body)
	}
	var kind masterdata.ItemKind
	if err := json.Unmarshal(createdKind.Body.Bytes(), &kind); err != nil {
		t.Fatal(err)
	}
	if kind.Code != "ASET-TETAP" || kind.Name != "Aset Tetap" || !kind.IsActive {
		t.Fatalf("jenis barang tidak dinormalisasi/default aktif: %#v", kind)
	}

	duplicateKind := request(http.MethodPost, "/api/v1/item-kinds", `{
		"code":"aset-tetap","name":"Duplikat"
	}`)
	if duplicateKind.Code != http.StatusConflict {
		t.Fatalf("kode jenis duplikat harus konflik, status=%d", duplicateKind.Code)
	}

	deactivateKind := request(
		http.MethodPatch,
		"/api/v1/item-kinds/"+kind.ID,
		`{"is_active":false}`,
	)
	if deactivateKind.Code != http.StatusOK {
		t.Fatalf("arsip jenis barang status=%d body=%s", deactivateKind.Code, deactivateKind.Body)
	}
	if err := json.Unmarshal(deactivateKind.Body.Bytes(), &kind); err != nil {
		t.Fatal(err)
	}
	if kind.IsActive {
		t.Fatal("is_active:false harus dipertahankan")
	}

	createdCategory := request(http.MethodPost, "/api/v1/categories", `{
		"code":" atk ","name":" Alat Tulis Kantor ","description":"Perlengkapan sekolah."
	}`)
	if createdCategory.Code != http.StatusCreated {
		t.Fatalf("buat kategori status=%d body=%s", createdCategory.Code, createdCategory.Body)
	}
	var category masterdata.Category
	if err := json.Unmarshal(createdCategory.Body.Bytes(), &category); err != nil {
		t.Fatal(err)
	}
	if category.Code != "ATK" || category.Name != "Alat Tulis Kantor" ||
		category.Description != "Perlengkapan sekolah." || !category.IsActive {
		t.Fatalf("kategori tidak dinormalisasi/default aktif: %#v", category)
	}

	longDescription := strings.Repeat("a", 2001)
	invalidCategoryBody, err := json.Marshal(map[string]string{
		"description": longDescription,
	})
	if err != nil {
		t.Fatal(err)
	}
	invalidDescription := request(
		http.MethodPatch,
		"/api/v1/categories/"+category.ID,
		string(invalidCategoryBody),
	)
	if invalidDescription.Code != http.StatusBadRequest {
		t.Fatalf("deskripsi terlalu panjang harus ditolak, status=%d", invalidDescription.Code)
	}

	store.user.Role = "pimpinan"
	listKinds := request(http.MethodGet, "/api/v1/item-kinds", "")
	if listKinds.Code != http.StatusOK {
		t.Fatalf("pimpinan boleh membaca jenis barang, status=%d", listKinds.Code)
	}
	listCategories := request(http.MethodGet, "/api/v1/categories", "")
	if listCategories.Code != http.StatusOK {
		t.Fatalf("pimpinan boleh membaca kategori, status=%d", listCategories.Code)
	}
	forbidden := request(http.MethodPost, "/api/v1/categories", `{
		"code":"LAB","name":"Laboratorium"
	}`)
	if forbidden.Code != http.StatusForbidden {
		t.Fatalf("pimpinan tidak boleh mengubah kategori, status=%d", forbidden.Code)
	}
}

// CATATAN PEMELIHARAAN: tes ini mengunci akses baca semua role, tulis Admin/
// Petugas, dan validasi input/pembaruan aset; subtest mutasi mengunci hak draft
// serta pembatalan. Validasi referensi aktif tetap harus dipertahankan di Mongo.
func TestAssetEndpointsValidateInputAndEnforceRoles(t *testing.T) {
	store := &memoryStore{user: users.User{
		ID:       "96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		Username: "admin",
		FullName: "Admin Sekolah",
		Role:     "admin",
		IsActive: true,
	}}
	api, err := New(
		store,
		store,
		[]byte("0123456789abcdef0123456789abcdef"),
		nil,
		log.New(io.Discard, "", 0),
	)
	if err != nil {
		t.Fatal(err)
	}

	// CATATAN PEMELIHARAAN: tes ini mengunci kontrak penyimpanan draft, validasi
	// jenis/lokasi/jumlah, pembatalan satu arah, dan izin baca/tulis per role.
	// Integrasi Mongo tetap perlu memakai koleksi yang telah di-init.
	t.Run("movement endpoints persist draft and enforce roles", func(t *testing.T) {
		store := &memoryStore{user: users.User{
			ID:       "96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
			Username: "admin",
			FullName: "Admin Sekolah",
			Role:     "admin",
			IsActive: true,
		}}
		api, err := New(
			store,
			store,
			[]byte("0123456789abcdef0123456789abcdef"),
			nil,
			log.New(io.Discard, "", 0),
		)
		if err != nil {
			t.Fatal(err)
		}
		token, _, err := api.tokens.Issue(store.user.ID, store.user.Role)
		if err != nil {
			t.Fatal(err)
		}
		handler := api.Handler()
		request := func(method, path, body string) *httptest.ResponseRecorder {
			req := httptest.NewRequest(method, path, strings.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+token)
			if body != "" {
				req.Header.Set("Content-Type", "application/json")
			}
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, req)
			return response
		}

		empty := request(http.MethodGet, "/api/v1/movements?page=1&page_size=10", "")
		if empty.Code != http.StatusOK || !strings.Contains(empty.Body.String(), `"total":0`) {
			t.Fatalf("daftar mutasi kosong harus berhasil, status=%d body=%s", empty.Code, empty.Body)
		}
		const itemID = "8a000002-0000-4000-8000-000000000002"
		const sourceID = "8a000003-0000-4000-8000-000000000003"
		const targetID = "8a000004-0000-4000-8000-000000000004"
		body := `{
			"movement_type":"transfer",
			"idempotency_key":"mutasi-test-001",
			"line":{
				"item_id":"` + itemID + `",
				"from_location_id":"` + sourceID + `",
				"to_location_id":"` + targetID + `",
				"quantity":2,
				"notes":"Pindah ke ruang baru."
			}
		}`
		created := request(http.MethodPost, "/api/v1/movements", body)
		if created.Code != http.StatusCreated {
			t.Fatalf("draft valid harus disimpan, status=%d body=%s", created.Code, created.Body)
		}
		var record movements.Record
		if err := json.Unmarshal(created.Body.Bytes(), &record); err != nil {
			t.Fatal(err)
		}
		if record.Status != "draft" || record.PerformedBy != "Admin Sekolah" ||
			len(record.Lines) != 1 || record.Lines[0].Quantity != 2 {
			t.Fatalf("record draft harus menyertakan baris dan pelaku dari sesi: %#v", record)
		}
		replayed := request(http.MethodPost, "/api/v1/movements", body)
		var replayedRecord movements.Record
		if err := json.Unmarshal(replayed.Body.Bytes(), &replayedRecord); err != nil {
			t.Fatal(err)
		}
		if replayed.Code != http.StatusCreated || replayedRecord.ID != record.ID {
			t.Fatalf("request idempotensi tidak boleh menggandakan draft: status=%d record=%#v", replayed.Code, replayedRecord)
		}
		conflictingReplay := request(
			http.MethodPost,
			"/api/v1/movements",
			strings.Replace(body, "Pindah ke ruang baru.", "Payload yang berbeda.", 1),
		)
		if conflictingReplay.Code != http.StatusConflict {
			t.Fatalf("kunci idempotensi yang dipakai untuk payload berbeda harus konflik, status=%d", conflictingReplay.Code)
		}

		invalidQuantity := request(http.MethodPost, "/api/v1/movements", `{
			"movement_type":"transfer","idempotency_key":"mutasi-test-invalid",
			"line":{"item_id":"`+itemID+`","from_location_id":"`+sourceID+`",
			"to_location_id":"`+targetID+`","quantity":0,"notes":""}
		}`)
		if invalidQuantity.Code != http.StatusBadRequest {
			t.Fatalf("jumlah nol harus ditolak, status=%d", invalidQuantity.Code)
		}
		sameLocation := request(http.MethodPost, "/api/v1/movements", `{
			"movement_type":"transfer","idempotency_key":"mutasi-test-same-location",
			"line":{"item_id":"`+itemID+`","from_location_id":"`+sourceID+`",
			"to_location_id":"`+sourceID+`","quantity":1,"notes":""}
		}`)
		if sameLocation.Code != http.StatusBadRequest {
			t.Fatalf("lokasi transfer yang sama harus ditolak, status=%d", sameLocation.Code)
		}

		cancelled := request(http.MethodPatch, "/api/v1/movements/"+record.ID+"/cancel", "")
		if cancelled.Code != http.StatusOK || !strings.Contains(cancelled.Body.String(), `"status":"cancelled"`) {
			t.Fatalf("draft harus dapat dibatalkan, status=%d body=%s", cancelled.Code, cancelled.Body)
		}
		cancelAgain := request(http.MethodPatch, "/api/v1/movements/"+record.ID+"/cancel", "")
		if cancelAgain.Code != http.StatusConflict {
			t.Fatalf("mutasi non-draft tidak boleh dibatalkan lagi, status=%d", cancelAgain.Code)
		}

		store.user.Role = "pimpinan"
		readOnly := request(http.MethodGet, "/api/v1/movements", "")
		if readOnly.Code != http.StatusOK {
			t.Fatalf("pimpinan boleh membaca mutasi, status=%d", readOnly.Code)
		}
		forbidden := request(http.MethodPost, "/api/v1/movements", body)
		if forbidden.Code != http.StatusForbidden {
			t.Fatalf("pimpinan tidak boleh membuat draft, status=%d", forbidden.Code)
		}
	})
	token, _, err := api.tokens.Issue(store.user.ID, store.user.Role)
	if err != nil {
		t.Fatal(err)
	}
	handler := api.Handler()
	request := func(method, path, body string) *httptest.ResponseRecorder {
		request := httptest.NewRequest(method, path, strings.NewReader(body))
		request.Header.Set("Authorization", "Bearer "+token)
		if body != "" {
			request.Header.Set("Content-Type", "application/json")
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		return response
	}

	empty := request(http.MethodGet, "/api/v1/assets?page=1&page_size=10", "")
	if empty.Code != http.StatusOK || !strings.Contains(empty.Body.String(), `"total":0`) {
		t.Fatalf("daftar aset kosong harus berhasil, status=%d body=%s", empty.Code, empty.Body)
	}
	invalidCategory := request(http.MethodPost, "/api/v1/assets", `{
		"name":"Laptop","category_id":"bukan-uuid",
		"location_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","condition":"Bagus"
	}`)
	if invalidCategory.Code != http.StatusBadRequest {
		t.Fatalf("kategori invalid harus ditolak, status=%d", invalidCategory.Code)
	}
	invalidCondition := request(http.MethodPost, "/api/v1/assets", `{
		"name":"Laptop","kind_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","category_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		"location_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","condition":"tidak dikenal"
	}`)
	if invalidCondition.Code != http.StatusBadRequest {
		t.Fatalf("kondisi tidak dikenal harus ditolak, status=%d", invalidCondition.Code)
	}
	created := request(http.MethodPost, "/api/v1/assets", `{
		"name":"Laptop ruang guru","kind_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","category_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		"location_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","condition":"Bagus"
	}`)
	if created.Code != http.StatusCreated {
		t.Fatalf("aset valid harus dibuat, status=%d body=%s", created.Code, created.Body)
	}
	var asset inventory.Record
	if err := json.Unmarshal(created.Body.Bytes(), &asset); err != nil {
		t.Fatal(err)
	}
	if asset.AssetID == "" || asset.AssetCode == "" || len(asset.Events) != 1 {
		t.Fatalf("response harus memuat aset dan event awal: %#v", asset)
	}
	stockCreated := request(http.MethodPost, "/api/v1/stock-items", `{
		"name":"Kertas A4","kind_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		"category_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","unit":"rim",
		"minimum_stock":2,"location_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","initial_quantity":5
	}`)
	if stockCreated.Code != http.StatusCreated || !strings.Contains(stockCreated.Body.String(), `"quantity":5`) {
		t.Fatalf("barang stok dan saldo awal harus tersimpan, status=%d body=%s", stockCreated.Code, stockCreated.Body)
	}
	stockList := request(http.MethodGet, "/api/v1/stock-items", "")
	if stockList.Code != http.StatusOK || !strings.Contains(stockList.Body.String(), `"total":1`) {
		t.Fatalf("daftar barang stok harus memuat barang baru, status=%d body=%s", stockList.Code, stockList.Body)
	}
	stockEdited := request(http.MethodPatch, "/api/v1/stock-items/8a000004-0000-4000-8000-000000000004", `{"name":"Kertas A4","category_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","unit":"rim","minimum_stock":2,"location_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","quantity":4,"notes":"Koreksi salah hitung."}`)
	if stockEdited.Code != http.StatusOK || !strings.Contains(stockEdited.Body.String(), `"quantity":4`) {
		t.Fatalf("koreksi barang stok harus berhasil, status=%d body=%s", stockEdited.Code, stockEdited.Body)
	}

	change := request(http.MethodPatch, "/api/v1/assets/"+asset.AssetID+"/condition", `{
		"condition":"Perlu perbaikan","notes":"Engsel perlu diperiksa."
	}`)
	if change.Code != http.StatusOK {
		t.Fatalf("perubahan kondisi valid harus berhasil, status=%d body=%s", change.Code, change.Body)
	}
	if !strings.Contains(change.Body.String(), `"performed_by":"Admin Sekolah"`) ||
		!strings.Contains(change.Body.String(), `"notes":"Engsel perlu diperiksa."`) {
		t.Fatalf("response harus menyertakan riwayat audit: %s", change.Body)
	}
	sameCondition := request(http.MethodPatch, "/api/v1/assets/"+asset.AssetID+"/condition", `{
		"condition":"Perlu perbaikan","notes":"Tidak berubah."
	}`)
	if sameCondition.Code != http.StatusConflict {
		t.Fatalf("kondisi yang sama harus ditolak, status=%d", sameCondition.Code)
	}
	store.user.Role = "pimpinan"
	readOnly := request(http.MethodGet, "/api/v1/assets", "")
	if readOnly.Code != http.StatusOK {
		t.Fatalf("pimpinan boleh membaca aset, status=%d", readOnly.Code)
	}
	forbidden := request(http.MethodPost, "/api/v1/assets", `{
		"name":"Tidak boleh dibuat","category_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40",
		"location_id":"96e3e808-9bcb-4e8d-a5a2-fb6c66bc7f40","condition":"Bagus"
	}`)
	if forbidden.Code != http.StatusForbidden {
		t.Fatalf("pimpinan tidak boleh membuat aset, status=%d", forbidden.Code)
	}
	store.user.Role = "petugas"
	allowed := request(http.MethodPatch, "/api/v1/assets/"+asset.AssetID+"/condition", `{
		"condition":"Rusak","notes":"Uji petugas."
	}`)
	if allowed.Code != http.StatusOK {
		t.Fatalf("petugas boleh mencatat kondisi aset, status=%d body=%s", allowed.Code, allowed.Body)
	}
	archived := request(http.MethodPatch, "/api/v1/assets/"+asset.AssetID+"/archive", "")
	if archived.Code != http.StatusOK || !strings.Contains(archived.Body.String(), `"status":"archived"`) {
		t.Fatalf("aset harus dapat dinonaktifkan, status=%d body=%s", archived.Code, archived.Body)
	}
}
