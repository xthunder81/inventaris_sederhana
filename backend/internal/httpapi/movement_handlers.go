package httpapi

import (
	"context"
	"errors"
	"math"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/movements"
)

// CATATAN PEMELIHARAAN: kontrak ini mengelola draft mutasi beserta barisnya;
// adapter Mongo memvalidasi referensi aktif dan tidak mengubah saldo. Posting
// harus ditambahkan sebagai operasi transaksi terpisah sebelum status posted
// pernah diizinkan dari API.
type MovementStore interface {
	CountMovements(context.Context) (int64, error)
	ListMovements(context.Context, int64, int64) ([]movements.Record, error)
	CreateMovement(context.Context, movements.CreateInput, string, string) (movements.Record, error)
	CancelMovement(context.Context, string) (movements.Record, error)
	PostMovement(context.Context, string, string) (movements.Record, error)
}

type createMovementRequest struct {
	Type           string `json:"movement_type"`
	IdempotencyKey string `json:"idempotency_key"`
	Line           struct {
		ItemID       string  `json:"item_id"`
		FromLocation *string `json:"from_location_id"`
		ToLocation   *string `json:"to_location_id"`
		Quantity     float64 `json:"quantity"`
		Notes        string  `json:"notes"`
	} `json:"line"`
}

func (api *API) listMovements(writer http.ResponseWriter, request *http.Request) {
	if api.movementStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan mutasi belum tersedia")
		return
	}
	page, pageSize, err := parsePage(request)
	if err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}
	total, err := api.movementStore.CountMovements(request.Context())
	if err != nil {
		api.logger.Printf("gagal menghitung mutasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar mutasi belum dapat dimuat")
		return
	}
	result, err := api.movementStore.ListMovements(
		request.Context(), (page-1)*pageSize, pageSize,
	)
	if err != nil {
		api.logger.Printf("gagal memuat mutasi: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar mutasi belum dapat dimuat")
		return
	}
	if result == nil {
		result = []movements.Record{}
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"data": result, "total": total, "page": page, "page_size": pageSize,
	})
}

func (api *API) createMovement(writer http.ResponseWriter, request *http.Request) {
	if api.movementStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan mutasi belum tersedia")
		return
	}
	var body createMovementRequest
	if !decodeJSON(writer, request, &body) {
		return
	}
	body.Type = strings.ToLower(strings.TrimSpace(body.Type))
	body.IdempotencyKey = strings.TrimSpace(body.IdempotencyKey)
	body.Line.ItemID = strings.TrimSpace(body.Line.ItemID)
	body.Line.Notes = strings.TrimSpace(body.Line.Notes)
	if !validMovementType(body.Type) {
		writeError(writer, http.StatusBadRequest, "jenis mutasi tidak valid")
		return
	}
	if body.IdempotencyKey == "" || utf8.RuneCountInString(body.IdempotencyKey) > 128 {
		writeError(writer, http.StatusBadRequest, "kunci idempotensi wajib diisi dan maksimal 128 karakter")
		return
	}
	if _, err := uuid.Parse(body.Line.ItemID); err != nil {
		writeError(writer, http.StatusBadRequest, "barang mutasi tidak valid")
		return
	}
	if !validMovementLocationID(body.Line.FromLocation) ||
		!validMovementLocationID(body.Line.ToLocation) {
		writeError(writer, http.StatusBadRequest, "lokasi mutasi tidak valid")
		return
	}
	if body.Line.Quantity < 0.000001 ||
		math.IsNaN(body.Line.Quantity) ||
		math.IsInf(body.Line.Quantity, 0) {
		writeError(writer, http.StatusBadRequest, "jumlah mutasi harus lebih besar dari 0")
		return
	}
	if utf8.RuneCountInString(body.Line.Notes) > 1000 {
		writeError(writer, http.StatusBadRequest, "catatan maksimal 1000 karakter")
		return
	}
	if !validMovementLocations(body.Type, body.Line.FromLocation, body.Line.ToLocation) {
		writeError(writer, http.StatusBadRequest, "lokasi asal dan tujuan tidak sesuai jenis mutasi")
		return
	}

	actor, err := api.store.FindByID(request.Context(), claimsFromContext(request.Context()).UserID)
	if err != nil {
		api.logger.Printf("gagal memuat pelaku pencatatan mutasi: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	input := movements.CreateInput{
		Type:           body.Type,
		IdempotencyKey: body.IdempotencyKey,
		Line: movements.LineInput{
			ItemID: body.Line.ItemID, FromLocation: body.Line.FromLocation,
			ToLocation: body.Line.ToLocation, Quantity: body.Line.Quantity,
			Notes: body.Line.Notes,
		},
	}
	api.movementWrites.Lock()
	defer api.movementWrites.Unlock()
	record, err := api.movementStore.CreateMovement(
		request.Context(), input, actor.ID, actor.FullName,
	)
	if err != nil {
		api.writeMovementError(writer, err, "draft mutasi belum dapat disimpan")
		return
	}
	writeJSON(writer, http.StatusCreated, record)
}

func (api *API) cancelMovement(writer http.ResponseWriter, request *http.Request) {
	if api.movementStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan mutasi belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id mutasi tidak valid")
		return
	}
	api.movementWrites.Lock()
	defer api.movementWrites.Unlock()
	record, err := api.movementStore.CancelMovement(request.Context(), id)
	if err != nil {
		api.writeMovementError(writer, err, "draft mutasi belum dapat dibatalkan")
		return
	}
	writeJSON(writer, http.StatusOK, record)
}

// CATATAN PEMELIHARAAN: actor diambil dari sesi terautentikasi; penyimpanan
// wajib memposting status, saldo, dan audit secara atomik di replica set.
func (api *API) postMovement(writer http.ResponseWriter, request *http.Request) {
	if api.movementStore == nil {
		writeError(writer, http.StatusServiceUnavailable, "layanan mutasi belum tersedia")
		return
	}
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id mutasi tidak valid")
		return
	}
	actor, err := api.store.FindByID(request.Context(), claimsFromContext(request.Context()).UserID)
	if err != nil {
		api.logger.Printf("gagal memuat pelaku posting mutasi: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	api.movementWrites.Lock()
	defer api.movementWrites.Unlock()
	record, err := api.movementStore.PostMovement(request.Context(), id, actor.ID)
	if err != nil {
		api.writeMovementError(writer, err, "mutasi belum dapat diposting")
		return
	}
	writeJSON(writer, http.StatusOK, record)
}

func (api *API) writeMovementError(writer http.ResponseWriter, err error, fallback string) {
	switch {
	case errors.Is(err, movements.ErrConflict):
		writeError(writer, http.StatusConflict, "kunci idempotensi telah dipakai untuk data berbeda")
	case errors.Is(err, movements.ErrNotFound):
		writeError(writer, http.StatusNotFound, "mutasi tidak ditemukan")
	case errors.Is(err, movements.ErrInvalidState):
		writeError(writer, http.StatusConflict, "aksi ini hanya dapat dilakukan pada draft")
	case errors.Is(err, movements.ErrInvalidTarget):
		writeError(writer, http.StatusBadRequest, "barang dan lokasi harus aktif dan valid")
	case errors.Is(err, movements.ErrInsufficientStock):
		writeError(writer, http.StatusConflict, "saldo stok tidak mencukupi untuk mutasi ini")
	case errors.Is(err, movements.ErrTransactionsUnavailable):
		writeError(writer, http.StatusServiceUnavailable, "posting memerlukan MongoDB replica set; saldo belum diubah")
	default:
		api.logger.Printf("%s: %v", fallback, err)
		writeError(writer, http.StatusInternalServerError, fallback)
	}
}

func validMovementType(value string) bool {
	switch value {
	case "receipt", "issue", "transfer", "adjustment":
		return true
	default:
		return false
	}
}

func validMovementLocationID(id *string) bool {
	if id == nil {
		return true
	}
	_, err := uuid.Parse(*id)
	return err == nil
}

func validMovementLocations(kind string, from, to *string) bool {
	switch kind {
	case "receipt", "adjustment":
		return from == nil && to != nil
	case "issue":
		return from != nil && to == nil
	case "transfer":
		return from != nil && to != nil && *from != *to
	default:
		return false
	}
}
