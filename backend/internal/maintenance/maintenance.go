package maintenance

import (
	"errors"
	"time"
)

var (
	ErrNotFound         = errors.New("laporan pemeliharaan tidak ditemukan")
	ErrInvalidReference = errors.New("aset atau pelapor tidak valid")
	ErrInvalidState     = errors.New("transisi status pemeliharaan tidak valid")
	ErrConcurrentEdit   = errors.New("laporan berubah oleh permintaan lain")
)

type CreateInput struct {
	AssetID     string
	Description string
}

type UpdateInput struct {
	Status string
	Cost   float64
}

type Record struct {
	ID           string     `json:"id"`
	AssetID      string     `json:"asset_id"`
	AssetCode    string     `json:"asset_code"`
	AssetName    string     `json:"asset_name"`
	ReportedBy   string     `json:"reported_by"`
	ReportedByID string     `json:"-"`
	Status       string     `json:"status"`
	Description  string     `json:"description"`
	Cost         float64    `json:"cost"`
	ReportedAt   time.Time  `json:"reported_at"`
	ClosedAt     *time.Time `json:"closed_at"`
}

func CanTransition(from, to string) bool {
	switch from {
	case "reported":
		return to == "in_progress" || to == "cancelled"
	case "in_progress":
		return to == "completed" || to == "cancelled"
	default:
		return false
	}
}
