package httpapi

import (
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"inventaris_sederhana/backend/internal/users"
)

var usernamePattern = regexp.MustCompile(`^[a-z0-9._-]{3,64}$`)

// CATATAN PEMELIHARAAN: total dihitung menggunakan filter query yang sama
// dengan List; bila daftar pengguna diberi filter/status, terapkan ke keduanya.
func (api *API) listUsers(writer http.ResponseWriter, request *http.Request) {
	page, pageSize, err := parsePage(request)
	if err != nil {
		writeError(writer, http.StatusBadRequest, err.Error())
		return
	}
	total, err := api.store.Count(request.Context())
	if err != nil {
		api.logger.Printf("gagal menghitung pengguna: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar pengguna belum dapat dimuat")
		return
	}
	result, err := api.store.List(request.Context(), (page-1)*pageSize, pageSize)
	if err != nil {
		api.logger.Printf("gagal memuat pengguna: %v", err)
		writeError(writer, http.StatusInternalServerError, "daftar pengguna belum dapat dimuat")
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"data":      result,
		"page":      page,
		"page_size": pageSize,
		"total":     total,
	})
}

// CATATAN PEMELIHARAAN: pembuatan akun mewajibkan kata sandi awal karena UI
// belum punya alur undangan/reset admin; jangan pernah menerima password_hash
// dari request.
type createUserRequest struct {
	Username string `json:"username"`
	FullName string `json:"full_name"`
	Role     string `json:"role"`
	Password string `json:"password"`
}

// CATATAN PEMELIHARAAN: username dinormalisasi sebelum indeks unik, role
// divalidasi terhadap enum Mongo, dan kata sandi di-hash sebelum insert.
// Jika form Flutter berubah, pertahankan kewajiban password awal atau rancang
// alur undangan yang mengirim token sekali pakai, bukan kata sandi lewat log.
func (api *API) createUser(writer http.ResponseWriter, request *http.Request) {
	var input createUserRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	username := strings.ToLower(strings.TrimSpace(input.Username))
	fullName := strings.TrimSpace(input.FullName)
	role := strings.ToLower(strings.TrimSpace(input.Role))
	if !usernamePattern.MatchString(username) || fullName == "" ||
		utf8.RuneCountInString(fullName) > 200 ||
		!validRole(role) || !validPassword(input.Password) {
		writeError(writer, http.StatusBadRequest, "data pengguna tidak valid; kata sandi harus 12–128 karakter")
		return
	}
	passwordHash, err := api.hashPassword(request.Context(), input.Password)
	if err != nil {
		api.logger.Printf("gagal membuat hash kata sandi: %v", err)
		writeError(writer, http.StatusInternalServerError, "pengguna belum dapat dibuat")
		return
	}
	now := time.Now().UTC()
	user := users.User{
		ID:           uuid.NewString(),
		Username:     username,
		FullName:     fullName,
		PasswordHash: passwordHash,
		Role:         role,
		IsActive:     true,
		CreatedAt:    now,
		UpdatedAt:    &now,
	}
	if err := api.store.Create(request.Context(), user); err != nil {
		if err == users.ErrConflict {
			writeError(writer, http.StatusConflict, "username sudah digunakan")
			return
		}
		api.logger.Printf("gagal menyimpan pengguna: %v", err)
		writeError(writer, http.StatusInternalServerError, "pengguna belum dapat dibuat")
		return
	}
	writeJSON(writer, http.StatusCreated, user)
}

// CATATAN PEMELIHARAAN: pointer membedakan field yang tidak dikirim dari
// `is_active:false`; decoder menolak field ekstra agar password tidak dapat
// diubah melalui endpoint edit profil admin.
type updateUserRequest struct {
	Username *string `json:"username"`
	FullName *string `json:"full_name"`
	Role     *string `json:"role"`
	IsActive *bool   `json:"is_active"`
}

// CATATAN PEMELIHARAAN: hanya admin dapat mengubah username/nama/peran/status.
// Username tetap tunduk pada indeks unik; admin tidak boleh menonaktifkan atau
// menurunkan peran dirinya sendiri agar tidak mengunci sesi aktifnya.
func (api *API) updateUser(writer http.ResponseWriter, request *http.Request) {
	id := request.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(writer, http.StatusBadRequest, "id pengguna tidak valid")
		return
	}
	var input updateUserRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	update := users.Update{}
	if input.Username != nil {
		username := strings.ToLower(strings.TrimSpace(*input.Username))
		if !usernamePattern.MatchString(username) {
			writeError(writer, http.StatusBadRequest, "username harus 3–64 karakter dan hanya memakai huruf kecil, angka, titik, garis bawah, atau tanda hubung")
			return
		}
		update.Username = &username
	}
	if input.FullName != nil {
		fullName := strings.TrimSpace(*input.FullName)
		if fullName == "" || utf8.RuneCountInString(fullName) > 200 {
			writeError(writer, http.StatusBadRequest, "nama lengkap harus 1–200 karakter")
			return
		}
		update.FullName = &fullName
	}
	if input.Role != nil {
		role := strings.ToLower(strings.TrimSpace(*input.Role))
		if !validRole(role) {
			writeError(writer, http.StatusBadRequest, "peran tidak valid")
			return
		}
		update.Role = &role
	}
	if input.IsActive != nil {
		update.IsActive = input.IsActive
	}
	if update.Username == nil && update.FullName == nil &&
		update.Role == nil && update.IsActive == nil {
		writeError(writer, http.StatusBadRequest, "tidak ada perubahan yang dikirim")
		return
	}
	claims := claimsFromContext(request.Context())
	if claims.UserID == id &&
		((update.IsActive != nil && !*update.IsActive) ||
			(update.Role != nil && *update.Role != "admin")) {
		writeError(writer, http.StatusConflict, "admin tidak dapat menonaktifkan atau menurunkan perannya sendiri")
		return
	}
	user, err := api.store.Update(request.Context(), id, update)
	if err != nil {
		if err == users.ErrConflict {
			writeError(writer, http.StatusConflict, "username sudah digunakan")
			return
		}
		writeStoreError(api.logger, writer, err)
		return
	}
	writeJSON(writer, http.StatusOK, user)
}

// CATATAN PEMELIHARAAN: enum harus sama dengan validator users.role di init.js
// dan mapping label role pada klien Flutter.
func validRole(role string) bool {
	return role == "admin" || role == "petugas" || role == "pimpinan"
}
