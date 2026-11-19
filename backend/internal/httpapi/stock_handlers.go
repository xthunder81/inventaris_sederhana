package httpapi

import (
	"context"
	"math"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/inventory"
)

// CATATAN PEMELIHARAAN: stok bukan unit barcode; kontrak ini hanya membuat
// item ber-tracking_mode=stock dan saldo pembuka pada satu lokasi aktif.
type StockItemStore interface {
	ListStockItems(context.Context) ([]inventory.StockItem, error)
	CreateStockItem(context.Context, inventory.StockItemInput) (inventory.StockItem, error)
	UpdateStockItem(context.Context, string, inventory.StockItemUpdateInput, string) (inventory.StockItem, error)
}

type createStockItemRequest struct {
	Name            string  `json:"name"`
	KindID          string  `json:"kind_id"`
	CategoryID      string  `json:"category_id"`
	Unit            string  `json:"unit"`
	MinimumStock    float64 `json:"minimum_stock"`
	LocationID      string  `json:"location_id"`
	InitialQuantity float64 `json:"initial_quantity"`
}

type updateStockItemRequest struct {
	Name         string  `json:"name"`
	CategoryID   string  `json:"category_id"`
	Unit         string  `json:"unit"`
	MinimumStock float64 `json:"minimum_stock"`
	LocationID   string  `json:"location_id"`
	Quantity     float64 `json:"quantity"`
	Notes        string  `json:"notes"`
}

func (api *API) listStockItems(w http.ResponseWriter, r *http.Request) {
	if api.stockItemStore == nil {
		writeError(w, http.StatusServiceUnavailable, "layanan stok belum tersedia")
		return
	}
	items, err := api.stockItemStore.ListStockItems(r.Context())
	if err != nil {
		api.logger.Printf("gagal memuat daftar stok: %v", err)
		writeError(w, http.StatusInternalServerError, "daftar barang habis pakai belum dapat dimuat")
		return
	}
	if items == nil {
		items = []inventory.StockItem{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"data": items, "total": len(items)})
}

func (api *API) createStockItem(w http.ResponseWriter, r *http.Request) {
	if api.stockItemStore == nil {
		writeError(w, http.StatusServiceUnavailable, "layanan stok belum tersedia")
		return
	}
	var body createStockItemRequest
	if !decodeJSON(w, r, &body) {
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	body.KindID = strings.TrimSpace(body.KindID)
	body.CategoryID = strings.TrimSpace(body.CategoryID)
	body.LocationID = strings.TrimSpace(body.LocationID)
	body.Unit = strings.TrimSpace(body.Unit)
	if body.Name == "" || utf8.RuneCountInString(body.Name) > 200 {
		writeError(w, http.StatusBadRequest, "nama barang wajib diisi dan maksimal 200 karakter")
		return
	}
	if _, err := uuid.Parse(body.KindID); err != nil {
		writeError(w, http.StatusBadRequest, "jenis barang tidak valid")
		return
	}
	if _, err := uuid.Parse(body.CategoryID); err != nil {
		writeError(w, http.StatusBadRequest, "kategori barang tidak valid")
		return
	}
	if _, err := uuid.Parse(body.LocationID); err != nil {
		writeError(w, http.StatusBadRequest, "lokasi stok tidak valid")
		return
	}
	if body.Unit == "" || utf8.RuneCountInString(body.Unit) > 32 {
		writeError(w, http.StatusBadRequest, "satuan wajib diisi dan maksimal 32 karakter")
		return
	}
	if body.MinimumStock < 0 || math.IsNaN(body.MinimumStock) || math.IsInf(body.MinimumStock, 0) || body.InitialQuantity < 0 || math.IsNaN(body.InitialQuantity) || math.IsInf(body.InitialQuantity, 0) {
		writeError(w, http.StatusBadRequest, "stok minimum dan jumlah awal harus berupa angka nol atau lebih")
		return
	}
	api.inventoryWrites.Lock()
	defer api.inventoryWrites.Unlock()
	item, err := api.stockItemStore.CreateStockItem(r.Context(), inventory.StockItemInput{Name: body.Name, KindID: body.KindID, CategoryID: body.CategoryID, Unit: body.Unit, MinimumStock: body.MinimumStock, LocationID: body.LocationID, InitialQuantity: body.InitialQuantity})
	if err != nil {
		api.writeInventoryError(w, err, "barang habis pakai belum dapat dibuat")
		return
	}
	writeJSON(w, http.StatusCreated, item)
}

// CATATAN PEMELIHARAAN: edit saldo selalu per lokasi dan alasan wajib; storage
// menulis adjustment posted agar koreksi jumlah dapat ditelusuri setelahnya.
func (api *API) updateStockItem(w http.ResponseWriter, r *http.Request) {
	if api.stockItemStore == nil {
		writeError(w, http.StatusServiceUnavailable, "layanan stok belum tersedia")
		return
	}
	id := r.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, http.StatusBadRequest, "id barang stok tidak valid")
		return
	}
	var body updateStockItemRequest
	if !decodeJSON(w, r, &body) {
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	body.CategoryID = strings.TrimSpace(body.CategoryID)
	body.LocationID = strings.TrimSpace(body.LocationID)
	body.Unit = strings.TrimSpace(body.Unit)
	body.Notes = strings.TrimSpace(body.Notes)
	if body.Name == "" || utf8.RuneCountInString(body.Name) > 200 {
		writeError(w, http.StatusBadRequest, "nama barang wajib diisi dan maksimal 200 karakter")
		return
	}
	if _, err := uuid.Parse(body.CategoryID); err != nil {
		writeError(w, http.StatusBadRequest, "kategori barang tidak valid")
		return
	}
	if _, err := uuid.Parse(body.LocationID); err != nil {
		writeError(w, http.StatusBadRequest, "lokasi stok tidak valid")
		return
	}
	if body.Unit == "" || utf8.RuneCountInString(body.Unit) > 32 {
		writeError(w, http.StatusBadRequest, "satuan wajib diisi dan maksimal 32 karakter")
		return
	}
	if body.MinimumStock < 0 || math.IsNaN(body.MinimumStock) || math.IsInf(body.MinimumStock, 0) || body.Quantity < 0 || math.IsNaN(body.Quantity) || math.IsInf(body.Quantity, 0) {
		writeError(w, http.StatusBadRequest, "stok dan batas minimum harus berupa angka nol atau lebih")
		return
	}
	if body.Notes == "" || utf8.RuneCountInString(body.Notes) > 500 {
		writeError(w, http.StatusBadRequest, "alasan koreksi wajib diisi dan maksimal 500 karakter")
		return
	}
	actor, err := api.store.FindByID(r.Context(), claimsFromContext(r.Context()).UserID)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "akun petugas belum dapat diverifikasi")
		return
	}
	api.inventoryWrites.Lock()
	defer api.inventoryWrites.Unlock()
	item, err := api.stockItemStore.UpdateStockItem(r.Context(), id, inventory.StockItemUpdateInput{Name: body.Name, CategoryID: body.CategoryID, Unit: body.Unit, MinimumStock: body.MinimumStock, LocationID: body.LocationID, Quantity: body.Quantity, Notes: body.Notes}, actor.ID)
	if err != nil {
		api.writeInventoryError(w, err, "barang habis pakai belum dapat diperbarui")
		return
	}
	writeJSON(w, http.StatusOK, item)
}
