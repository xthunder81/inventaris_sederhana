package users

import (
	"errors"
	"time"
)

var (
	ErrNotFound = errors.New("pengguna tidak ditemukan")
	ErrConflict = errors.New("username sudah digunakan")
)

// CATATAN PEMELIHARAAN: tag BSON harus sesuai users pada database/mongo/init.js.
// PasswordHash sengaja dikecualikan dari JSON; jangan menghapus json:"-" atau
// mengirim dokumen BSON langsung tanpa DTO yang aman.
type User struct {
	ID           string     `bson:"_id" json:"id"`
	Username     string     `bson:"username" json:"username"`
	FullName     string     `bson:"full_name" json:"full_name"`
	PasswordHash string     `bson:"password_hash" json:"-"`
	Role         string     `bson:"role" json:"role"`
	IsActive     bool       `bson:"is_active" json:"is_active"`
	LastLoginAt  *time.Time `bson:"last_login_at,omitempty" json:"last_login_at,omitempty"`
	CreatedAt    time.Time  `bson:"created_at" json:"created_at"`
	UpdatedAt    *time.Time `bson:"updated_at,omitempty" json:"updated_at,omitempty"`
}

// CATATAN PEMELIHARAAN: event login menyimpan hasil dan waktu, bukan kredensial.
// Jika field ditambah, selaraskan validator login_events dan batas retensi data.
type LoginEvent struct {
	UserID     *string   `bson:"user_id"`
	Username   string    `bson:"username"`
	Result     string    `bson:"result"`
	OccurredAt time.Time `bson:"occurred_at"`
}

// CATATAN PEMELIHARAAN: pointer membedakan field PATCH yang tidak dikirim dari
// nilai false/kosong yang memang diminta; tambahkan field baru di validator,
// handler, dan pemetaan Mongo bila format update berkembang.
type Update struct {
	Username *string
	FullName *string
	Role     *string
	IsActive *bool
}
