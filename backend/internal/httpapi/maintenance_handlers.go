package httpapi

import (
	"context"
	"math"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/maintenance"
)

// CATATAN PEMELIHARAAN: petugas membuat laporan untuk aset aktif; backend
// mengambil pelapor dari token. Pembaruan hanya mengizinkan transisi status
// yang disetujui dan biaya akhir yang valid, tanpa mengubah kondisi aset.
type MaintenanceStore interface {
	CountMaintenance(context.Context) (int64, error)
	ListMaintenance(context.Context, int64, int64) ([]maintenance.Record, error)
	CreateMaintenance(context.Context, maintenance.CreateInput, string) (maintenance.Record, error)
	UpdateMaintenance(context.Context, string, maintenance.UpdateInput) (maintenance.Record, error)
}

type createMaintenanceRequest struct {
	AssetID     string `json:"asset_id"`
	Description string `json:"description"`
}

type updateMaintenanceRequest struct {
	Status string  `json:"status"`
	Cost   float64 `json:"cost"`
}

func (api *API) listMaintenance(w http.ResponseWriter, r *http.Request) {
	if api.maintenanceStore == nil {
		writeError(w, http.StatusServiceUnavailable, "layanan pemeliharaan belum tersedia")
		return
	}
	page, pageSize, err := parsePage(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	total, err := api.maintenanceStore.CountMaintenance(r.Context())
	if err != nil {
		api.logger.Printf("gagal menghitung laporan pemeliharaan: %v", err)
		writeError(w, http.StatusInternalServerError, "daftar pemeliharaan belum dapat dimuat")
		return
	}
	records, err := api.maintenanceStore.ListMaintenance(r.Context(), (page-1)*pageSize, pageSize)
	if err != nil {
		api.logger.Printf("gagal memuat laporan pemeliharaan: %v", err)
		writeError(w, http.StatusInternalServerError, "daftar pemeliharaan belum dapat dimuat")
		return
	}
	if records == nil {
		records = []maintenance.Record{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"data": records, "total": total, "page": page, "page_size": pageSize})
}

func (api *API) createMaintenance(w http.ResponseWriter, r *http.Request) {
	if api.maintenanceStore == nil {
		writeError(w, http.StatusServiceUnavailable, "layanan pemeliharaan belum tersedia")
		return
	}
	var body createMaintenanceRequest
	if !decodeJSON(w, r, &body) {
		return
	}
	body.AssetID = strings.TrimSpace(body.AssetID)
	body.Description = strings.TrimSpace(body.Description)
	if _, err := uuid.Parse(body.AssetID); err != nil {
		writeError(w, http.StatusBadRequest, "aset pemeliharaan tidak valid")
		return
	}
	if body.Description == "" || utf8.RuneCountInString(body.Description) > 4000 {
		writeError(w, http.StatusBadRequest, "keluhan wajib diisi dan maksimal 4000 karakter")
		return
	}
	actor := claimsFromContext(r.Context()).UserID
	api.maintenanceWrites.Lock()
	defer api.maintenanceWrites.Unlock()
	record, err := api.maintenanceStore.CreateMaintenance(r.Context(), maintenance.CreateInput{AssetID: body.AssetID, Description: body.Description}, actor)
	if err != nil {
		api.writeMaintenanceError(w, err, "laporan pemeliharaan belum dapat disimpan")
		return
	}
	writeJSON(w, http.StatusCreated, record)
}

func (api *API) updateMaintenance(w http.ResponseWriter, r *http.Request) {
	if api.maintenanceStore == nil {
		writeError(w, http.StatusServiceUnavailable, "layanan pemeliharaan belum tersedia")
		return
	}
	id := r.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, http.StatusBadRequest, "id laporan pemeliharaan tidak valid")
		return
	}
	var body updateMaintenanceRequest
	if !decodeJSON(w, r, &body) {
		return
	}
	body.Status = strings.TrimSpace(body.Status)
	if body.Status != "in_progress" && body.Status != "completed" && body.Status != "cancelled" {
		writeError(w, http.StatusBadRequest, "status pemeliharaan tidak valid")
		return
	}
	if body.Cost < 0 || math.IsNaN(body.Cost) || math.IsInf(body.Cost, 0) {
		writeError(w, http.StatusBadRequest, "biaya pemeliharaan harus nol atau lebih")
		return
	}
	api.maintenanceWrites.Lock()
	defer api.maintenanceWrites.Unlock()
	record, err := api.maintenanceStore.UpdateMaintenance(r.Context(), id, maintenance.UpdateInput{Status: body.Status, Cost: body.Cost})
	if err != nil {
		api.writeMaintenanceError(w, err, "laporan pemeliharaan belum dapat diperbarui")
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func (api *API) writeMaintenanceError(w http.ResponseWriter, err error, fallback string) {
	switch {
	case err == maintenance.ErrNotFound:
		writeError(w, http.StatusNotFound, "laporan pemeliharaan tidak ditemukan")
	case err == maintenance.ErrInvalidReference:
		writeError(w, http.StatusBadRequest, "aset harus aktif dan valid")
	case err == maintenance.ErrInvalidState:
		writeError(w, http.StatusConflict, "transisi status pemeliharaan tidak diizinkan")
	case err == maintenance.ErrConcurrentEdit:
		writeError(w, http.StatusConflict, "laporan berubah; muat ulang lalu coba lagi")
	default:
		api.logger.Printf("%s: %v", fallback, err)
		writeError(w, http.StatusInternalServerError, fallback)
	}
}
