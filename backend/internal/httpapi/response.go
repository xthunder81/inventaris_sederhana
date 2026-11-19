package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"

	"inventaris_sederhana/backend/internal/users"
)

const maxJSONBody = 1 << 20

// CATATAN PEMELIHARAAN: payload dibatasi 1 MiB dan field tak dikenal ditolak
// agar typo/field sensitif tidak diterima diam-diam; tambah field request pada
// DTO sebelum memperluas kontrak API.
func decodeJSON(writer http.ResponseWriter, request *http.Request, destination any) bool {
	request.Body = http.MaxBytesReader(writer, request.Body, maxJSONBody)
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		writeError(writer, http.StatusBadRequest, "format JSON tidak valid")
		return false
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		writeError(writer, http.StatusBadRequest, "permintaan harus berisi satu objek JSON")
		return false
	}
	return true
}

// CATATAN PEMELIHARAAN: semua response JSON menggunakan satu writer untuk
// mempertahankan Content-Type dan nosniff; error encode dicatat karena header
// mungkin sudah terkirim dan tidak dapat diganti dengan fallback.
func writeJSON(writer http.ResponseWriter, status int, value any) {
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.Header().Set("X-Content-Type-Options", "nosniff")
	writer.WriteHeader(status)
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		log.Printf("gagal menulis response JSON: %v", err)
	}
}

// CATATAN PEMELIHARAAN: bentuk error API diseragamkan pada key `error`; ubah
// bersama klien Flutter bila response contract perlu kode/field tambahan.
func writeError(writer http.ResponseWriter, status int, message string) {
	writeJSON(writer, status, map[string]string{"error": message})
}

// CATATAN PEMELIHARAAN: not-found menjadi 404, sedangkan kegagalan DB lain
// dicatat internal dan disamarkan pada response agar detail driver tidak bocor.
func writeStoreError(logger *log.Logger, writer http.ResponseWriter, err error) {
	if errors.Is(err, users.ErrNotFound) {
		writeError(writer, http.StatusNotFound, "pengguna tidak ditemukan")
		return
	}
	logger.Printf("operasi pengguna gagal: %v", err)
	writeError(writer, http.StatusInternalServerError, "operasi pengguna belum dapat diproses")
}
