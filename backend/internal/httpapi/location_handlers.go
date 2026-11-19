package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/locations"
)

// CATATAN PEMELIHARAAN: repository master lokasi dipisah dari akun agar
// handler tetap dapat memakai store palsu sederhana; Mongo wajib menerapkan
// kontrak ini sebelum route lokasi dapat melayani request.
type LocationStore interface {
	ListLocations(context.Context) ([]locations.Location, error)
	CreateLocation(context.Context, locations.Location) error
	UpdateLocation(context.Context, string, locations.Location) (locations.Location, error)
}

type createLocationRequest struct {
	Code         string          `json:"code"`
	Name         string          `json:"name"`
	ParentID     json.RawMessage `json:"parent_id"`
	LocationType string          `json:"location_type"`
	IsActive     *bool           `json:"is_active"`
}

type updateLocationRequest struct {
	Code         *string         `json:"code"`
	Name         *string         `json:"name"`
	ParentID     json.RawMessage `json:"parent_id"`
	LocationType *string         `json:"location_type"`
	IsActive     *bool           `json:"is_active"`
}

// CATATAN PEMELIHARAAN: daftar mengembalikan seluruh lokasi, termasuk arsip,
// agar Admin dapat mengaktifkan kembali dan Pimpinan dapat melihat struktur.
// Petugas memakai data aktif pada pilihan operasional di klien.
func (api *API) listLocations(writer http.ResponseWriter, request *http.Request) {
	if api.locationStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan lokasi belum tersedia")
		return
	}
	result, err := api.locationStore.ListLocations(request.Context())
	if err != nil {
		api.logger.Printf("gagal memuat lokasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar lokasi belum dapat dimuat")
		return
	}
	if result == nil {
		result = []locations.Location{}
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"data":  result,
		"total": len(result),
	})
}

// CATATAN PEMELIHARAAN: Admin membuat lokasi aktif secara default; kode
// dinormalisasi sebelum pemeriksaan duplikasi dan penyimpanan, sementara
// parent_id null berarti lokasi tingkat atas.
func (api *API) createLocation(writer http.ResponseWriter, request *http.Request) {
	if api.locationStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan lokasi belum tersedia")
		return
	}
	var input createLocationRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	parentID, ok := decodeLocationParent(writer, input.ParentID, false)
	if !ok {
		return
	}
	isActive := true
	if input.IsActive != nil {
		isActive = *input.IsActive
	}
	location := locations.Location{
		ID:           uuid.NewString(),
		Code:         strings.ToUpper(strings.TrimSpace(input.Code)),
		Name:         strings.TrimSpace(input.Name),
		ParentID:     parentID,
		LocationType: strings.ToLower(strings.TrimSpace(input.LocationType)),
		IsActive:     isActive,
		CreatedAt:    time.Now().UTC(),
	}
	if message := validateLocationFields(location); message != "" {
		writeError(writer, http.StatusBadRequest, message)
		return
	}
	api.locationWrites.Lock()
	defer api.locationWrites.Unlock()
	existing, err := api.locationStore.ListLocations(request.Context())
	if err != nil {
		api.logger.Printf("gagal memeriksa struktur lokasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "lokasi belum dapat dibuat")
		return
	}
	if status, message := validateLocationRelations(location, "", existing); message != "" {
		writeError(writer, status, message)
		return
	}
	if err := api.locationStore.CreateLocation(request.Context(), location); err != nil {
		if errors.Is(err, locations.ErrConflict) {
			writeError(writer, http.StatusConflict, "kode lokasi sudah digunakan")
			return
		}
		api.logger.Printf("gagal menyimpan lokasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "lokasi belum dapat dibuat")
		return
	}
	writeJSON(writer, http.StatusCreated, location)
}

// CATATAN PEMELIHARAAN: PATCH hanya mengubah field yang dikirim; raw JSON
// membedakan parent_id yang tidak dikirim dari null untuk melepas induk.
// Pengarsipan tidak menghapus riwayat dan ditolak selama masih ada anak aktif.
func (api *API) updateLocation(writer http.ResponseWriter, request *http.Request) {
	if api.locationStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan lokasi belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id lokasi tidak valid")
		return
	}
	var input updateLocationRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	if input.Code == nil && input.Name == nil && len(input.ParentID) == 0 &&
		input.LocationType == nil && input.IsActive == nil {
		writeError(writer, http.StatusBadRequest, "tidak ada perubahan yang dikirim")
		return
	}
	parentID, parentProvided := (*string)(nil), len(input.ParentID) > 0
	if parentProvided {
		var ok bool
		parentID, ok = decodeLocationParent(writer, input.ParentID, true)
		if !ok {
			return
		}
	}
	api.locationWrites.Lock()
	defer api.locationWrites.Unlock()
	existing, err := api.locationStore.ListLocations(request.Context())
	if err != nil {
		api.logger.Printf("gagal memeriksa struktur lokasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "lokasi belum dapat diubah")
		return
	}
	var current locations.Location
	found := false
	for _, item := range existing {
		if item.ID == id {
			current = item
			found = true
			break
		}
	}
	if !found {
		writeError(writer, http.StatusNotFound, "lokasi tidak ditemukan")
		return
	}
	if input.Code != nil {
		current.Code = strings.ToUpper(strings.TrimSpace(*input.Code))
	}
	if input.Name != nil {
		current.Name = strings.TrimSpace(*input.Name)
	}
	if parentProvided {
		current.ParentID = parentID
	}
	if input.LocationType != nil {
		current.LocationType = strings.ToLower(strings.TrimSpace(*input.LocationType))
	}
	if input.IsActive != nil {
		current.IsActive = *input.IsActive
	}
	updatedAt := time.Now().UTC()
	current.UpdatedAt = &updatedAt

	if message := validateLocationFields(current); message != "" {
		writeError(writer, http.StatusBadRequest, message)
		return
	}
	if status, message := validateLocationRelations(current, id, existing); message != "" {
		writeError(writer, status, message)
		return
	}
	updated, err := api.locationStore.UpdateLocation(request.Context(), id, current)
	if err != nil {
		if errors.Is(err, locations.ErrNotFound) {
			writeError(writer, http.StatusNotFound, "lokasi tidak ditemukan")
			return
		}
		if errors.Is(err, locations.ErrConflict) {
			writeError(writer, http.StatusConflict, "kode lokasi sudah digunakan")
			return
		}
		api.logger.Printf("gagal memperbarui lokasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "lokasi belum dapat diubah")
		return
	}
	writeJSON(writer, http.StatusOK, updated)
}

func decodeLocationParent(writer http.ResponseWriter, raw json.RawMessage, required bool) (*string, bool) {
	if len(raw) == 0 {
		if required {
			writeError(writer, http.StatusBadRequest, "parent_id harus dikirim")
			return nil, false
		}
		return nil, true
	}
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return nil, true
	}
	var value string
	if err := json.Unmarshal(raw, &value); err != nil {
		writeError(writer, http.StatusBadRequest, "parent_id harus berupa teks atau null")
		return nil, false
	}
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, true
	}
	return &value, true
}

func validateLocationFields(location locations.Location) string {
	if location.Code == "" || utf8.RuneCountInString(location.Code) > 64 {
		return "kode lokasi wajib diisi dan maksimal 64 karakter"
	}
	if location.Name == "" || utf8.RuneCountInString(location.Name) > 200 {
		return "nama lokasi wajib diisi dan maksimal 200 karakter"
	}
	switch location.LocationType {
	case "sekolah", "gedung", "ruang", "gudang", "area", "lainnya":
		return ""
	default:
		return "jenis lokasi tidak valid"
	}
}

func validateLocationRelations(location locations.Location, currentID string, existing []locations.Location) (int, string) {
	byID := make(map[string]locations.Location, len(existing))
	for _, item := range existing {
		byID[item.ID] = item
		if item.ID != currentID && strings.EqualFold(item.Code, location.Code) {
			return http.StatusConflict, "kode lokasi sudah digunakan"
		}
	}
	if !location.IsActive {
		for _, item := range existing {
			if item.IsActive && item.ParentID != nil && *item.ParentID == location.ID {
				return http.StatusConflict, "lokasi memiliki turunan aktif; arsipkan turunannya terlebih dahulu"
			}
		}
	}
	if location.ParentID == nil {
		return 0, ""
	}
	parent, found := byID[*location.ParentID]
	if !found {
		return http.StatusBadRequest, "lokasi induk tidak ditemukan"
	}
	if !parent.IsActive {
		return http.StatusConflict, "lokasi induk harus aktif"
	}
	visited := make(map[string]bool)
	for id := location.ParentID; id != nil; {
		if *id == location.ID {
			return http.StatusConflict, "lokasi tidak boleh menjadi induk bagi dirinya sendiri atau turunannya"
		}
		if visited[*id] {
			return http.StatusConflict, "struktur lokasi induk mengandung siklus"
		}
		visited[*id] = true
		ancestor, exists := byID[*id]
		if !exists {
			return http.StatusConflict, "struktur lokasi induk tidak valid"
		}
		id = ancestor.ParentID
	}
	return 0, ""
}
