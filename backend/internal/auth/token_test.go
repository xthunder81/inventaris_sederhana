package auth

import (
	"testing"
	"time"
)

// CATATAN PEMELIHARAAN: tes mempertahankan round-trip claims ID/peran agar
// perubahan format token tidak merusak middleware autentikasi.
func TestTokenIssueAndParse(t *testing.T) {
	manager := NewTokenManager([]byte("0123456789abcdef0123456789abcdef"))
	token, _, err := manager.Issue("user-1", "admin")
	if err != nil {
		t.Fatal(err)
	}
	claims, err := manager.Parse(token)
	if err != nil {
		t.Fatal(err)
	}
	if claims.UserID != "user-1" || claims.Role != "admin" {
		t.Fatalf("klaim token tidak sesuai: %#v", claims)
	}
}

// CATATAN PEMELIHARAAN: token expired harus tetap gagal meski signature valid;
// jam yang dikendalikan membuat batas masa berlaku dapat diuji deterministik.
func TestExpiredTokenIsRejected(t *testing.T) {
	manager := NewTokenManager([]byte("0123456789abcdef0123456789abcdef"))
	manager.now = func() time.Time { return time.Unix(1_800_000_000, 0) }
	token, _, err := manager.Issue("user-1", "admin")
	if err != nil {
		t.Fatal(err)
	}
	manager.now = func() time.Time { return time.Unix(1_800_000_901, 0) }
	if _, err := manager.Parse(token); err == nil {
		t.Fatal("token yang kedaluwarsa harus ditolak")
	}
}
