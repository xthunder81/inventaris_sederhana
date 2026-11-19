package config

import (
	"errors"
	"os"
	"strings"
)

type Config struct {
	HTTPAddress  string
	MongoURI     string
	DatabaseName string
	JWTSecret    []byte
	CORSOrigins  []string
}

// CATATAN PEMELIHARAAN: konfigurasi dikumpulkan saat startup supaya salah
// setel rahasia JWT menghentikan server sebelum menerima request; variabel
// konfigurasi baru perlu ditambahkan ke Config dan panduan README.
func Load() (Config, error) {
	secret := os.Getenv("JWT_SECRET")
	if len(secret) < 32 {
		return Config{}, errors.New("JWT_SECRET harus berisi minimal 32 karakter")
	}

	return Config{
		HTTPAddress:  envOrDefault("HTTP_ADDR", "127.0.0.1:8081"),
		MongoURI:     envOrDefault("MONGODB_URI", "mongodb://127.0.0.1:27017"),
		DatabaseName: envOrDefault("MONGODB_DATABASE", "inventaris_sederhana"),
		JWTSecret:    []byte(secret),
		CORSOrigins:  corsOrigins(),
	}, nil
}

// CATATAN PEMELIHARAAN: nilai kosong dan whitespace memakai default lokal;
// gunakan nama env yang terdokumentasi agar konfigurasi server tidak berbeda
// diam-diam antara development dan deployment.
func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// CATATAN PEMELIHARAAN: daftar origin dipisah koma dan whitespace dibuang;
// origin tetap dicocokkan persis oleh middleware CORS, bukan sebagai pola.
func splitList(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if origin := strings.TrimSpace(part); origin != "" {
			result = append(result, origin)
		}
	}
	return result
}

// CATATAN PEMELIHARAAN: default hanya mengizinkan origin loopback yang dipakai
// Flutter Web lokal; deployment harus mengisi CORS_ALLOWED_ORIGINS dengan
// origin frontend yang tepat agar layanan lain tidak dipercaya secara implisit.
func corsOrigins() []string {
	if origins := splitList(os.Getenv("CORS_ALLOWED_ORIGINS")); len(origins) > 0 {
		return origins
	}
	return []string{
		"http://localhost:8080",
		"http://127.0.0.1:8080",
		"http://localhost:5173",
		"http://127.0.0.1:5173",
	}
}
