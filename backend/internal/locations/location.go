package locations

import (
	"errors"
	"time"
)

var (
	ErrNotFound = errors.New("lokasi tidak ditemukan")
	ErrConflict = errors.New("kode lokasi sudah digunakan")
)

// CATATAN PEMELIHARAAN: parent_id boleh null untuk lokasi tingkat atas;
// field dan batas panjang harus tetap cocok dengan validator MongoDB.
type Location struct {
	ID           string     `bson:"_id" json:"id"`
	Code         string     `bson:"code" json:"code"`
	Name         string     `bson:"name" json:"name"`
	ParentID     *string    `bson:"parent_id" json:"parent_id"`
	LocationType string     `bson:"location_type" json:"location_type"`
	IsActive     bool       `bson:"is_active" json:"is_active"`
	CreatedAt    time.Time  `bson:"created_at" json:"created_at"`
	UpdatedAt    *time.Time `bson:"updated_at,omitempty" json:"updated_at,omitempty"`
}
