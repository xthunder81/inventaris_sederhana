package movements

import (
	"errors"
	"time"
)

var (
	ErrConflict                = errors.New("kunci idempotensi atau nomor mutasi sudah digunakan")
	ErrNotFound                = errors.New("mutasi tidak ditemukan")
	ErrInvalidState            = errors.New("mutasi bukan draft")
	ErrInvalidTarget           = errors.New("referensi mutasi tidak valid")
	ErrInsufficientStock       = errors.New("saldo stok tidak mencukupi")
	ErrTransactionsUnavailable = errors.New("posting memerlukan MongoDB replica set")
)

type LineInput struct {
	ItemID       string
	FromLocation *string
	ToLocation   *string
	Quantity     float64
	Notes        string
}

type CreateInput struct {
	Type           string
	IdempotencyKey string
	Line           LineInput
}

type Line struct {
	LineNumber     int     `json:"line_number"`
	ItemID         string  `json:"item_id"`
	ItemName       string  `json:"item_name"`
	FromLocationID *string `json:"from_location_id"`
	FromLocation   *string `json:"from_location_name"`
	ToLocationID   *string `json:"to_location_id"`
	ToLocation     *string `json:"to_location_name"`
	Quantity       float64 `json:"quantity"`
	Notes          string  `json:"notes"`
}

type Record struct {
	ID             string     `json:"id"`
	MovementNumber string     `json:"movement_number"`
	Type           string     `json:"movement_type"`
	Status         string     `json:"status"`
	IdempotencyKey string     `json:"idempotency_key"`
	PerformedByID  string     `json:"-"`
	PerformedBy    string     `json:"performed_by"`
	CreatedAt      time.Time  `json:"created_at"`
	PostedAt       *time.Time `json:"posted_at"`
	Lines          []Line     `json:"lines"`
}
