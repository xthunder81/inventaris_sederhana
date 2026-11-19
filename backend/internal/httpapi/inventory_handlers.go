package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/inventory"
)

// CATATAN PEMELIHARAAN: kontrak ini membatasi handler ke operasi aset yang
// dibutuhkan UI; adapter Mongo mengimplementasikan validasi referensi aktif,
// penyimpanan unit, dan event tanpa membuat handler bergantung pada driver.
type InventoryStore interface {
	CountAssets(context.Context) (int64, error)
	ListAssets(context.Context, int64, int64) ([]inventory.Record, error)
	CreateAsset(context.Context, inventory.CreateInput, string, string) (inventory.Record, error)
	ChangeAssetCondition(context.Context, string, string, string, string, string) (inventory.Record, error)
	UpdateAsset(context.Context, string, inventory.UpdateInput, string, string) (inventory.Record, error)
	ArchiveAsset(context.Context, string, string, string) error
}

type createAssetRequest struct {
	Name       string `json:"name"`
	KindID     string `json:"kind_id"`
	CategoryID string `json:"category_id"`
	LocationID string `json:"location_id"`
	Condition  string `json:"condition"`
}

type changeAssetConditionRequest struct {
	Condition string `json:"condition"`
	Notes     string `json:"notes"`
}

type updateAssetRequest struct {
	Name       string `json:"name"`
	KindID     string `json:"kind_id"`
	CategoryID string `json:"category_id"`
	LocationID string `json:"location_id"`
	Condition  string `json:"condition"`
}

// CATATAN PEMELIHARAAN: edit selalu memvalidasi ulang master aktif; adapter
// Mongo memisahkan item induk bila masih dipakai unit lain dan menulis event.
func (api *API) updateAsset(writer http.ResponseWriter, request *http.Request) {
	if api.inventoryStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan inventaris belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id aset tidak valid")
		return
	}
	var body updateAssetRequest
	if !decodeJSON(writer, request, &body) {
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	body.KindID = strings.TrimSpace(body.KindID)
	body.CategoryID = strings.TrimSpace(body.CategoryID)
	body.LocationID = strings.TrimSpace(body.LocationID)
	condition, valid := parseCondition(body.Condition)
	if _, err := uuid.Parse(body.KindID); err != nil {
		writeError(writer, http.StatusBadRequest, "jenis barang tidak valid")
		return
	}
	if body.Name == "" || utf8.RuneCountInString(body.Name) > 200 {
		writeError(writer, http.StatusBadRequest, "nama barang wajib diisi dan maksimal 200 karakter")
		return
	}
	if _, err := uuid.Parse(body.CategoryID); err != nil {
		writeError(writer, http.StatusBadRequest, "kategori barang tidak valid")
		return
	}
	if _, err := uuid.Parse(body.LocationID); err != nil {
		writeError(writer, http.StatusBadRequest, "lokasi barang tidak valid")
		return
	}
	if !valid {
		writeError(writer, http.StatusBadRequest, "kondisi aset tidak valid")
		return
	}
	actor, err := api.store.FindByID(request.Context(), claimsFromContext(request.Context()).UserID)
	if err != nil {
		writeError(writer, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	api.inventoryWrites.Lock()
	defer api.inventoryWrites.Unlock()
	record, err := api.inventoryStore.UpdateAsset(request.Context(), id, inventory.UpdateInput{Name: body.Name, KindID: body.KindID, CategoryID: body.CategoryID, LocationID: body.LocationID, ConditionCode: condition}, actor.ID, actor.FullName)
	if err != nil {
		api.writeInventoryError(writer, err, "aset belum dapat diperbarui")
		return
	}
	writeJSON(writer, http.StatusOK, record)
}

// CATATAN PEMELIHARAAN: daftar berisi aset aktif saja; data tetap dipaginasi
// agar API tidak mengirim seluruh riwayat inventaris dalam satu response.
func (api *API) listAssets(writer http.ResponseWriter, request *http.Request) {
	if api.inventoryStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan inventaris belum tersedia")
		return
	}
	page, pageSize, err := parsePage(request)
	if err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}
	total, err := api.inventoryStore.CountAssets(request.Context())
	if err != nil {
		api.logger.Printf("gagal menghitung aset: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar inventaris belum dapat dimuat")
		return
	}
	items, err := api.inventoryStore.ListAssets(request.Context(), (page-1)*pageSize, pageSize)
	if err != nil {
		api.logger.Printf("gagal memuat aset: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar inventaris belum dapat dimuat")
		return
	}
	if items == nil {
		items = []inventory.Record{}
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"data": items, "total": total, "page": page, "page_size": pageSize,
	})
}

// CATATAN PEMELIHARAAN: satu POST selalu membuat satu unit aset; item induk
// dipakai ulang hanya jika nama, jenis barang, dan kategori cocok.
// Item induk yang sempat tersimpan saat pembuatan aset gagal tetap sah sebagai
// katalog, karena Mongo standalone tidak menyediakan transaksi lintas dokumen.
func (api *API) createAsset(writer http.ResponseWriter, request *http.Request) {
	if api.inventoryStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan inventaris belum tersedia")
		return
	}
	var input createAssetRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	input.KindID = strings.TrimSpace(input.KindID)
	input.CategoryID = strings.TrimSpace(input.CategoryID)
	input.LocationID = strings.TrimSpace(input.LocationID)
	conditionCode, validCondition := parseCondition(input.Condition)
	if _, err := uuid.Parse(input.KindID); err != nil {
		writeError(writer, http.StatusBadRequest, "jenis barang tidak valid")
		return
	}
	if input.Name == "" || utf8.RuneCountInString(input.Name) > 200 {
		writeError(writer, http.StatusBadRequest, "nama barang wajib diisi dan maksimal 200 karakter")
		return
	}
	if _, err := uuid.Parse(input.CategoryID); err != nil {
		writeError(writer, http.StatusBadRequest, "kategori barang tidak valid")
		return
	}
	if _, err := uuid.Parse(input.LocationID); err != nil {
		writeError(writer, http.StatusBadRequest, "lokasi barang tidak valid")
		return
	}
	if !validCondition {
		writeError(writer, http.StatusBadRequest, "kondisi aset tidak valid")
		return
	}
	actor, err := api.store.FindByID(request.Context(), claimsFromContext(request.Context()).UserID)
	if err != nil {
		api.logger.Printf("gagal memuat pelaku pencatatan aset: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	api.inventoryWrites.Lock()
	defer api.inventoryWrites.Unlock()
	record, err := api.inventoryStore.CreateAsset(
		request.Context(),
		inventory.CreateInput{
			Name: input.Name, KindID: input.KindID, CategoryID: input.CategoryID,
			LocationID: input.LocationID, ConditionCode: conditionCode,
		},
		actor.ID,
		actor.FullName,
	)
	if err != nil {
		api.writeInventoryError(writer, err, "aset belum dapat dibuat")
		return
	}
	writeJSON(writer, http.StatusCreated, record)
}

// CATATAN PEMELIHARAAN: penonaktifan mengarsipkan aset, sehingga riwayat dan
// referensi transaksi tetap utuh; aset arsip tidak lagi masuk daftar aktif.
func (api *API) archiveAsset(writer http.ResponseWriter, request *http.Request) {
	if api.inventoryStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan inventaris belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id aset tidak valid")
		return
	}
	actor, err := api.store.FindByID(request.Context(), claimsFromContext(request.Context()).UserID)
	if err != nil {
		writeError(writer, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	api.inventoryWrites.Lock()
	defer api.inventoryWrites.Unlock()
	if err = api.inventoryStore.ArchiveAsset(request.Context(), id, actor.ID, actor.FullName); err != nil {
		api.writeInventoryError(writer, err, "aset belum dapat dinonaktifkan")
		return
	}
	writeJSON(writer, http.StatusOK, map[string]string{"status": "archived", "asset_id": id})
}

// CATATAN PEMELIHARAAN: kondisi berubah untuk satu ID aset, bukan semua item
// bernama sama. Kondisi lama dibandingkan atomik di Mongo; bila pencatatan
// event gagal, adapter mencoba memulihkan kondisi lama dan mengembalikan error.
func (api *API) changeAssetCondition(writer http.ResponseWriter, request *http.Request) {
	if api.inventoryStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan inventaris belum tersedia")
		return
	}
	assetID := request.PathValue("id")
	if _, err := uuid.Parse(assetID); err != nil {
		writeError(writer, http.StatusBadRequest, "id aset tidak valid")
		return
	}
	var input changeAssetConditionRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	conditionCode, validCondition := parseCondition(input.Condition)
	input.Notes = strings.TrimSpace(input.Notes)
	if !validCondition {
		writeError(writer, http.StatusBadRequest, "kondisi aset tidak valid")
		return
	}
	if input.Notes == "" || utf8.RuneCountInString(input.Notes) > 2000 {
		writeError(writer, http.StatusBadRequest, "catatan wajib diisi dan maksimal 2000 karakter")
		return
	}
	actor, err := api.store.FindByID(request.Context(), claimsFromContext(request.Context()).UserID)
	if err != nil {
		api.logger.Printf("gagal memuat pelaku perubahan kondisi: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	api.inventoryWrites.Lock()
	defer api.inventoryWrites.Unlock()
	record, err := api.inventoryStore.ChangeAssetCondition(
		request.Context(), assetID, conditionCode, input.Notes, actor.ID, actor.FullName,
	)
	if err != nil {
		api.writeInventoryError(writer, err, "kondisi aset belum dapat diperbarui")
		return
	}
	writeJSON(writer, http.StatusOK, record)
}

func (api *API) writeInventoryError(writer http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, inventory.ErrConflict):
		writeError(writer, http.StatusConflict, "data barang sudah ada atau kode sudah digunakan")
	case errors.Is(err, inventory.ErrNotFound):
		writeError(writer, http.StatusNotFound, "aset tidak ditemukan")
	case errors.Is(err, inventory.ErrInvalidReference):
		writeError(writer, http.StatusBadRequest, "jenis barang, kategori, lokasi, atau kondisi harus aktif dan sesuai")
	case errors.Is(err, inventory.ErrConditionSame):
		writeError(writer, http.StatusConflict, "kondisi aset tidak berubah")
	case errors.Is(err, inventory.ErrConcurrentEdit):
		writeError(writer, http.StatusConflict, "aset berubah oleh permintaan lain; muat ulang data")
	default:
		api.logger.Printf("%s: %v", fallback, err)
		writeError(writer, http.StatusInternalServerError, fallback)
	}
}

// CATATAN PEMELIHARAAN: label UI dipetakan ke code kondisi seed yang sudah ada.
// Jika kondisi di katalog diubah, selaraskan pilihan UI, code seed, dan mapping
// ini; penyimpanan selalu menggunakan ID condition aktif dari Mongo.
func parseCondition(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "bagus":
		return "bagus", true
	case "perlu perbaikan":
		return "perlu_perbaikan", true
	case "dalam service":
		return "dalam_service", true
	case "rusak":
		return "rusak", true
	default:
		return "", false
	}
}
