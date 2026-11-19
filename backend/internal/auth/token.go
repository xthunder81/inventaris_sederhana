package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

const tokenIssuer = "ruangsarana-api"

type Claims struct {
	UserID string `json:"sub"`
	Role   string `json:"role"`
	Issuer string `json:"iss"`
	Issued int64  `json:"iat"`
	Expiry int64  `json:"exp"`
}

type TokenManager struct {
	secret []byte
	now    func() time.Time
}

// CATATAN PEMELIHARAAN: secret disalin agar perubahan slice milik pemanggil
// tidak mengubah verifikasi token yang sudah berjalan; secret wajib dikelola
// di environment/secret store, bukan ditulis ke source atau log.
func NewTokenManager(secret []byte) *TokenManager {
	return &TokenManager{secret: append([]byte(nil), secret...), now: time.Now}
}

// CATATAN PEMELIHARAAN: token HS256 hanya menyimpan ID, peran, issuer, dan
// waktu; masa berlaku 15 menit diselaraskan dengan Parse dan dokumentasi API.
// Jangan tambahkan data pribadi atau kata sandi ke claims.
func (manager *TokenManager) Issue(userID, role string) (string, time.Time, error) {
	if len(manager.secret) < 32 {
		return "", time.Time{}, errors.New("kunci token tidak valid")
	}
	now := manager.now().UTC()
	expires := now.Add(15 * time.Minute)
	header, err := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	if err != nil {
		return "", time.Time{}, fmt.Errorf("buat header token: %w", err)
	}
	claims, err := json.Marshal(Claims{
		UserID: userID,
		Role:   role,
		Issuer: tokenIssuer,
		Issued: now.Unix(),
		Expiry: expires.Unix(),
	})
	if err != nil {
		return "", time.Time{}, fmt.Errorf("buat klaim token: %w", err)
	}
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." +
		base64.RawURLEncoding.EncodeToString(claims)
	signature := manager.sign(unsigned)
	return unsigned + "." + base64.RawURLEncoding.EncodeToString(signature), expires, nil
}

// CATATAN PEMELIHARAAN: validasi tanda tangan dilakukan sebelum claims dipakai;
// perubahan format, issuer, atau durasi harus tetap menolak token kedaluwarsa
// dan algoritma selain HS256.
func (manager *TokenManager) Parse(token string) (Claims, error) {
	var claims Claims
	parts := strings.Split(token, ".")
	if len(parts) != 3 || len(token) > 4096 {
		return claims, errors.New("token tidak valid")
	}
	unsigned := parts[0] + "." + parts[1]
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || !hmac.Equal(signature, manager.sign(unsigned)) {
		return claims, errors.New("token tidak valid")
	}
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return claims, errors.New("token tidak valid")
	}
	var header struct {
		Algorithm string `json:"alg"`
		Type      string `json:"typ"`
	}
	if json.Unmarshal(headerJSON, &header) != nil ||
		header.Algorithm != "HS256" ||
		header.Type != "JWT" {
		return claims, errors.New("token tidak valid")
	}
	claimsJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || json.Unmarshal(claimsJSON, &claims) != nil {
		return claims, errors.New("token tidak valid")
	}
	now := manager.now().Unix()
	if claims.UserID == "" || claims.Role == "" || claims.Issuer != tokenIssuer ||
		claims.Issued > now+60 || claims.Expiry <= now || claims.Expiry <= claims.Issued {
		return Claims{}, errors.New("token tidak valid")
	}
	return claims, nil
}

// CATATAN PEMELIHARAAN: signing selalu memakai HMAC-SHA256 yang dipilih tetap
// di sini; jangan menerima algoritma dari header token sebagai konfigurasi.
func (manager *TokenManager) sign(value string) []byte {
	mac := hmac.New(sha256.New, manager.secret)
	_, _ = mac.Write([]byte(value))
	return mac.Sum(nil)
}
