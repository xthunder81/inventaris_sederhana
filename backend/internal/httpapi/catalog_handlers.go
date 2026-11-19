package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/masterdata"
)

// CATATAN PEMELIHARAAN: jenis dan kategori adalah koleksi terpisah; backend
// memberikan kontrak eksplisit supaya validator dan indeks unik Mongo dapat
// diuji tanpa mengikat handler pada driver.
type CatalogStore interface {
	ListItemKinds(context.Context) ([]masterdata.ItemKind, error)
	CreateItemKind(context.Context, masterdata.ItemKind) error
	UpdateItemKind(context.Context, string, masterdata.ItemKind) (masterdata.ItemKind, error)
	ListCategories(context.Context) ([]masterdata.Category, error)
	CreateCategory(context.Context, masterdata.Category) error
	UpdateCategory(context.Context, string, masterdata.Category) (masterdata.Category, error)
}

type createItemKindRequest struct {
	Code     string `json:"code"`
	Name     string `json:"name"`
	IsActive *bool  `json:"is_active"`
}

type updateItemKindRequest struct {
	Code     *string `json:"code"`
	Name     *string `json:"name"`
	IsActive *bool   `json:"is_active"`
}

type createCategoryRequest struct {
	Code        string `json:"code"`
	Name        string `json:"name"`
	Description string `json:"description"`
	IsActive    *bool  `json:"is_active"`
}

type updateCategoryRequest struct {
	Code        *string `json:"code"`
	Name        *string `json:"name"`
	Description *string `json:"description"`
	IsActive    *bool   `json:"is_active"`
}

// CATATAN PEMELIHARAAN: daftar mencakup katalog aktif dan arsip agar Admin
// dapat mengaktifkan kembali record; perubahan sebaiknya memakai paginasi jika
// jumlah katalog tidak lagi kecil.
func (api *API) listItemKinds(writer http.ResponseWriter, request *http.Request) {
	if api.catalogStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan jenis barang belum tersedia")
		return
	}
	result, err := api.catalogStore.ListItemKinds(request.Context())
	if err != nil {
		api.logger.Printf("gagal memuat jenis barang: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar jenis barang belum dapat dimuat")
		return
	}
	if result == nil {
		result = []masterdata.ItemKind{}
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result, "total": len(result)})
}

// CATATAN PEMELIHARAAN: kode diubah ke uppercase sebelum cek duplikasi dan
// insert; indeks unik tetap menangani request bersamaan sebagai perlindungan
// terakhir. ItemKind hanya menyimpan kode, nama, dan status aktif.
func (api *API) createItemKind(writer http.ResponseWriter, request *http.Request) {
	if api.catalogStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan jenis barang belum tersedia")
		return
	}
	var input createItemKindRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	isActive := true
	if input.IsActive != nil {
		isActive = *input.IsActive
	}
	itemKind := masterdata.ItemKind{
		ID:       uuid.NewString(),
		Code:     strings.ToUpper(strings.TrimSpace(input.Code)),
		Name:     strings.TrimSpace(input.Name),
		IsActive: isActive,
	}
	if message := validateCatalogFields(itemKind.Code, itemKind.Name, 120); message != "" {
		writeError(writer, http.StatusBadRequest, message)
		return
	}
	existing, err := api.catalogStore.ListItemKinds(request.Context())
	if err != nil {
		api.logger.Printf("gagal memeriksa kode jenis barang: %v", err)
		writeError(writer, http.StatusInternalServerError, "jenis barang belum dapat dibuat")
		return
	}
	if hasDuplicateKindCode(existing, itemKind.Code, "") {
		writeError(writer, http.StatusConflict, "kode jenis barang sudah digunakan")
		return
	}
	if err := api.catalogStore.CreateItemKind(request.Context(), itemKind); err != nil {
		if errors.Is(err, masterdata.ErrConflict) {
			writeError(writer, http.StatusConflict, "kode jenis barang sudah digunakan")
			return
		}
		api.logger.Printf("gagal menyimpan jenis barang: %v", err)
		writeError(writer, http.StatusInternalServerError, "jenis barang belum dapat dibuat")
		return
	}
	writeJSON(writer, http.StatusCreated, itemKind)
}

// CATATAN PEMELIHARAAN: PATCH mempertahankan field yang tidak dikirim dan
// menolak request kosong. Status arsip tidak menghapus referensi barang lama.
func (api *API) updateItemKind(writer http.ResponseWriter, request *http.Request) {
	if api.catalogStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan jenis barang belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id jenis barang tidak valid")
		return
	}
	var input updateItemKindRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	if input.Code == nil && input.Name == nil && input.IsActive == nil {
		writeError(writer, http.StatusBadRequest, "tidak ada perubahan yang dikirim")
		return
	}
	existing, err := api.catalogStore.ListItemKinds(request.Context())
	if err != nil {
		api.logger.Printf("gagal memuat jenis barang untuk diubah: %v", err)
		writeError(writer, http.StatusInternalServerError, "jenis barang belum dapat diubah")
		return
	}
	var current masterdata.ItemKind
	found := false
	for _, item := range existing {
		if item.ID == id {
			current = item
			found = true
			break
		}
	}
	if !found {
		writeError(writer, http.StatusNotFound, "jenis barang tidak ditemukan")
		return
	}
	if input.Code != nil {
		current.Code = strings.ToUpper(strings.TrimSpace(*input.Code))
	}
	if input.Name != nil {
		current.Name = strings.TrimSpace(*input.Name)
	}
	if input.IsActive != nil {
		current.IsActive = *input.IsActive
	}
	if message := validateCatalogFields(current.Code, current.Name, 120); message != "" {
		writeError(writer, http.StatusBadRequest, message)
		return
	}
	if hasDuplicateKindCode(existing, current.Code, id) {
		writeError(writer, http.StatusConflict, "kode jenis barang sudah digunakan")
		return
	}
	updated, err := api.catalogStore.UpdateItemKind(request.Context(), id, current)
	if err != nil {
		if errors.Is(err, masterdata.ErrNotFound) {
			writeError(writer, http.StatusNotFound, "jenis barang tidak ditemukan")
			return
		}
		if errors.Is(err, masterdata.ErrConflict) {
			writeError(writer, http.StatusConflict, "kode jenis barang sudah digunakan")
			return
		}
		api.logger.Printf("gagal memperbarui jenis barang: %v", err)
		writeError(writer, http.StatusInternalServerError, "jenis barang belum dapat diubah")
		return
	}
	writeJSON(writer, http.StatusOK, updated)
}

// CATATAN PEMELIHARAAN: kategori mengikuti kontrak terpisah dengan deskripsi
// wajib tetapi boleh kosong sesuai schema categories; kode unik tetap dijaga
// oleh pemeriksaan API dan indeks Mongo.
func (api *API) listCategories(writer http.ResponseWriter, request *http.Request) {
	if api.catalogStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan kategori belum tersedia")
		return
	}
	result, err := api.catalogStore.ListCategories(request.Context())
	if err != nil {
		api.logger.Printf("gagal memuat kategori: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar kategori belum dapat dimuat")
		return
	}
	if result == nil {
		result = []masterdata.Category{}
	}
	writeJSON(writer, http.StatusOK, map[string]any{"data": result, "total": len(result)})
}

func (api *API) createCategory(writer http.ResponseWriter, request *http.Request) {
	if api.catalogStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan kategori belum tersedia")
		return
	}
	var input createCategoryRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	isActive := true
	if input.IsActive != nil {
		isActive = *input.IsActive
	}
	category := masterdata.Category{
		ID:          uuid.NewString(),
		Code:        strings.ToUpper(strings.TrimSpace(input.Code)),
		Name:        strings.TrimSpace(input.Name),
		Description: strings.TrimSpace(input.Description),
		IsActive:    isActive,
	}
	if message := validateCatalogFields(category.Code, category.Name, 120); message != "" {
		writeError(writer, http.StatusBadRequest, message)
		return
	}
	if utf8.RuneCountInString(category.Description) > 2000 {
		writeError(writer, http.StatusBadRequest, "deskripsi kategori maksimal 2000 karakter")
		return
	}
	existing, err := api.catalogStore.ListCategories(request.Context())
	if err != nil {
		api.logger.Printf("gagal memeriksa kode kategori: %v", err)
		writeError(writer, http.StatusInternalServerError, "kategori belum dapat dibuat")
		return
	}
	if hasDuplicateCategoryCode(existing, category.Code, "") {
		writeError(writer, http.StatusConflict, "kode kategori sudah digunakan")
		return
	}
	if err := api.catalogStore.CreateCategory(request.Context(), category); err != nil {
		if errors.Is(err, masterdata.ErrConflict) {
			writeError(writer, http.StatusConflict, "kode kategori sudah digunakan")
			return
		}
		api.logger.Printf("gagal menyimpan kategori: %v", err)
		writeError(writer, http.StatusInternalServerError, "kategori belum dapat dibuat")
		return
	}
	writeJSON(writer, http.StatusCreated, category)
}

// CATATAN PEMELIHARAAN: edit kategori mempertahankan description jika field
// tidak dikirim; nilai kosong yang dikirim sengaja menghapus deskripsi.
func (api *API) updateCategory(writer http.ResponseWriter, request *http.Request) {
	if api.catalogStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan kategori belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id kategori tidak valid")
		return
	}
	var input updateCategoryRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	if input.Code == nil && input.Name == nil && input.Description == nil && input.IsActive == nil {
		writeError(writer, http.StatusBadRequest, "tidak ada perubahan yang dikirim")
		return
	}
	existing, err := api.catalogStore.ListCategories(request.Context())
	if err != nil {
		api.logger.Printf("gagal memuat kategori untuk diubah: %v", err)
		writeError(writer, http.StatusInternalServerError, "kategori belum dapat diubah")
		return
	}
	var current masterdata.Category
	found := false
	for _, item := range existing {
		if item.ID == id {
			current = item
			found = true
			break
		}
	}
	if !found {
		writeError(writer, http.StatusNotFound, "kategori tidak ditemukan")
		return
	}
	if input.Code != nil {
		current.Code = strings.ToUpper(strings.TrimSpace(*input.Code))
	}
	if input.Name != nil {
		current.Name = strings.TrimSpace(*input.Name)
	}
	if input.Description != nil {
		current.Description = strings.TrimSpace(*input.Description)
	}
	if input.IsActive != nil {
		current.IsActive = *input.IsActive
	}
	if message := validateCatalogFields(current.Code, current.Name, 120); message != "" {
		writeError(writer, http.StatusBadRequest, message)
		return
	}
	if utf8.RuneCountInString(current.Description) > 2000 {
		writeError(writer, http.StatusBadRequest, "deskripsi kategori maksimal 2000 karakter")
		return
	}
	if hasDuplicateCategoryCode(existing, current.Code, id) {
		writeError(writer, http.StatusConflict, "kode kategori sudah digunakan")
		return
	}
	updated, err := api.catalogStore.UpdateCategory(request.Context(), id, current)
	if err != nil {
		if errors.Is(err, masterdata.ErrNotFound) {
			writeError(writer, http.StatusNotFound, "kategori tidak ditemukan")
			return
		}
		if errors.Is(err, masterdata.ErrConflict) {
			writeError(writer, http.StatusConflict, "kode kategori sudah digunakan")
			return
		}
		api.logger.Printf("gagal memperbarui kategori: %v", err)
		writeError(writer, http.StatusInternalServerError, "kategori belum dapat diubah")
		return
	}
	writeJSON(writer, http.StatusOK, updated)
}

func validateCatalogFields(code, name string, maxNameLength int) string {
	if code == "" || utf8.RuneCountInString(code) > 64 {
		return "kode wajib diisi dan maksimal 64 karakter"
	}
	if name == "" || utf8.RuneCountInString(name) > maxNameLength {
		return "nama wajib diisi dan maksimal 120 karakter"
	}
	return ""
}

func hasDuplicateKindCode(items []masterdata.ItemKind, code, exceptID string) bool {
	for _, item := range items {
		if item.ID != exceptID && strings.EqualFold(item.Code, code) {
			return true
		}
	}
	return false
}

func hasDuplicateCategoryCode(items []masterdata.Category, code, exceptID string) bool {
	for _, item := range items {
		if item.ID != exceptID && strings.EqualFold(item.Code, code) {
			return true
		}
	}
	return false
}
