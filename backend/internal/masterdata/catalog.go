package masterdata

import "errors"

var (
	ErrNotFound = errors.New("data master tidak ditemukan")
	ErrConflict = errors.New("kode katalog sudah digunakan")
)

// CATATAN PEMELIHARAAN: field harus sama dengan schema item_kinds pada
// database/mongo/init.js; koleksi ini tidak menyimpan timestamp.
type ItemKind struct {
	ID       string `bson:"_id" json:"id"`
	Code     string `bson:"code" json:"code"`
	Name     string `bson:"name" json:"name"`
	IsActive bool   `bson:"is_active" json:"is_active"`
}

// CATATAN PEMELIHARAAN: deskripsi wajib ada di Mongo walau isinya boleh kosong;
// perubahan DTO harus menjaga kontrak tersebut saat create dan update.
type Category struct {
	ID          string `bson:"_id" json:"id"`
	Code        string `bson:"code" json:"code"`
	Name        string `bson:"name" json:"name"`
	Description string `bson:"description" json:"description"`
	IsActive    bool   `bson:"is_active" json:"is_active"`
}
