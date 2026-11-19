package inventory

import "time"

// CATATAN PEMELIHARAAN: saldo disimpan per item dan lokasi; item stok tidak
// mempunyai barcode unit seperti aset. Jumlah awal dibuat bersama katalog.
type StockItemInput struct {
	Name            string
	KindID          string
	CategoryID      string
	Unit            string
	MinimumStock    float64
	LocationID      string
	InitialQuantity float64
}

type StockItemUpdateInput struct {
	Name         string
	CategoryID   string
	Unit         string
	MinimumStock float64
	LocationID   string
	Quantity     float64
	Notes        string
}

type StockBalance struct {
	LocationID string    `json:"location_id"`
	Location   string    `json:"location"`
	Quantity   float64   `json:"quantity"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type StockItem struct {
	ItemID       string         `json:"item_id"`
	Code         string         `json:"item_code"`
	Name         string         `json:"name"`
	KindID       string         `json:"kind_id"`
	CategoryID   string         `json:"category_id"`
	Category     string         `json:"category"`
	Unit         string         `json:"unit"`
	MinimumStock float64        `json:"minimum_stock"`
	Balances     []StockBalance `json:"balances"`
}
