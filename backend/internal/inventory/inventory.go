package inventory

import (
	"errors"
	"time"
)

var (
	ErrConflict         = errors.New("kode aset sudah digunakan")
	ErrNotFound         = errors.New("aset tidak ditemukan")
	ErrInvalidReference = errors.New("referensi aset tidak valid")
	ErrConditionSame    = errors.New("kondisi aset tidak berubah")
	ErrConcurrentEdit   = errors.New("aset berubah oleh permintaan lain")
)

type CreateInput struct {
	Name          string
	KindID        string
	CategoryID    string
	LocationID    string
	ConditionCode string
}

type UpdateInput = CreateInput

type Record struct {
	AssetID     string      `json:"asset_id"`
	ItemID      string      `json:"item_id"`
	KindID      string      `json:"kind_id"`
	AssetCode   string      `json:"asset_code"`
	Name        string      `json:"name"`
	CategoryID  string      `json:"category_id"`
	Category    string      `json:"category"`
	LocationID  string      `json:"location_id"`
	Location    string      `json:"location"`
	ConditionID string      `json:"condition_id"`
	Condition   string      `json:"condition"`
	CreatedAt   time.Time   `json:"created_at"`
	Events      []EventView `json:"events"`
}

type EventView struct {
	EventType         string    `json:"event_type"`
	PreviousCondition string    `json:"previous_condition"`
	NewCondition      string    `json:"new_condition"`
	PerformedBy       string    `json:"performed_by"`
	Notes             string    `json:"notes"`
	OccurredAt        time.Time `json:"occurred_at"`
}
