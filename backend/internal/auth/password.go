package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	argonMemory      uint32 = 64 * 1024
	argonIterations  uint32 = 3
	argonParallelism uint8  = 1
	argonKeyLength   uint32 = 32
	saltLength              = 16
)

// CATATAN PEMELIHARAAN: hash yang disimpan di users.password_hash memakai
// salt acak per akun. Jika parameter Argon2id diubah, perbarui VerifyPassword,
// siapkan dukungan baca hash lama atau migrasi, lalu ukur beban RAM/CPU login.
func HashPassword(password string) (string, error) {
	if password == "" {
		return "", errors.New("kata sandi tidak boleh kosong")
	}
	salt := make([]byte, saltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("buat salt kata sandi: %w", err)
	}
	hash := argon2.IDKey(
		[]byte(password),
		salt,
		argonIterations,
		argonMemory,
		argonParallelism,
		argonKeyLength,
	)
	return fmt.Sprintf(
		"$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		argonMemory,
		argonIterations,
		argonParallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

// CATATAN PEMELIHARAAN: hanya format dan parameter hash yang dibuat server
// saat ini yang diterima; pembatasan ini mencegah hash rusak meminta RAM/CPU
// berlebihan. Perubahan parameter harus disertai kebijakan migrasi hash.
func VerifyPassword(encodedHash, password string) bool {
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 || parts[1] != "argon2id" || parts[2] != "v=19" {
		return false
	}
	parameters := map[string]uint64{}
	for _, parameter := range strings.Split(parts[3], ",") {
		keyValue := strings.SplitN(parameter, "=", 2)
		if len(keyValue) != 2 {
			return false
		}
		value, err := strconv.ParseUint(keyValue[1], 10, 32)
		if err != nil {
			return false
		}
		parameters[keyValue[0]] = value
	}
	memory, hasMemory := parameters["m"]
	iterations, hasIterations := parameters["t"]
	parallelism, hasParallelism := parameters["p"]
	if !hasMemory || !hasIterations || !hasParallelism ||
		memory != uint64(argonMemory) ||
		iterations != uint64(argonIterations) ||
		parallelism != uint64(argonParallelism) {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil || len(salt) < 8 || len(salt) > 64 {
		return false
	}
	expected, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil || len(expected) != int(argonKeyLength) {
		return false
	}
	actual := argon2.IDKey(
		[]byte(password),
		salt,
		uint32(iterations),
		uint32(memory),
		uint8(parallelism),
		uint32(len(expected)),
	)
	return subtle.ConstantTimeCompare(actual, expected) == 1
}
