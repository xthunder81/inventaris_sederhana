package httpapi

import (
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"inventaris_sederhana/backend/internal/users"
)

// CATATAN PEMELIHARAAN: DTO ini hanya memuat kredensial masuk; jangan tambahkan
// field role/status dari klien karena keduanya harus diambil dari dokumen DB.
type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// CATATAN PEMELIHARAAN: login menormalisasi username, memverifikasi akun aktif,
// mencatat hasil ke login_events, memperbarui last_login_at, lalu menerbitkan
// token. Perubahan alur pencatatan harus tetap gagal secara eksplisit bila
// penyimpanan log gagal; response tidak boleh menyertakan password_hash.
func (api *API) login(writer http.ResponseWriter, request *http.Request) {
	var input loginRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	username := strings.ToLower(strings.TrimSpace(input.Username))
	if username == "" || len(username) > 128 ||
		input.Password == "" || utf8.RuneCountInString(input.Password) > 256 {
		writeError(writer, http.StatusBadRequest, "username dan kata sandi wajib diisi")
		return
	}

	user, err := api.store.FindByUsername(request.Context(), username)
	if err != nil && err != users.ErrNotFound {
		api.logger.Printf("login gagal membaca pengguna: %v", err)
		writeError(writer, http.StatusInternalServerError, "login belum dapat diproses")
		return
	}
	found := err == nil
	hash := api.dummyHash
	var userID *string
	if found {
		hash = user.PasswordHash
		userID = &user.ID
	}
	passwordMatches, err := api.verifyPassword(request.Context(), hash, input.Password)
	if err != nil {
		api.logger.Printf("verifikasi kata sandi gagal diproses: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "login belum dapat diproses")
		return
	}
	if !found || !passwordMatches || !user.IsActive {
		if err := api.store.RecordLogin(request.Context(), users.LoginEvent{
			UserID:     userID,
			Username:   username,
			Result:     "failed",
			OccurredAt: time.Now().UTC(),
		}); err != nil {
			api.logger.Printf("gagal mencatat login yang ditolak: %v", err)
			writeError(writer, http.StatusInternalServerError, "login belum dapat diproses")
			return
		}
		writeError(writer, http.StatusUnauthorized, "username atau kata sandi tidak valid")
		return
	}

	now := time.Now().UTC()
	if err := api.store.UpdateLastLogin(request.Context(), user.ID, now); err != nil {
		api.logger.Printf("gagal memperbarui waktu login: %v", err)
		writeError(writer, http.StatusInternalServerError, "login belum dapat diproses")
		return
	}
	user.LastLoginAt = &now
	user.UpdatedAt = &now
	if err := api.store.RecordLogin(request.Context(), users.LoginEvent{
		UserID:     &user.ID,
		Username:   username,
		Result:     "success",
		OccurredAt: now,
	}); err != nil {
		api.logger.Printf("gagal mencatat login berhasil: %v", err)
		writeError(writer, http.StatusInternalServerError, "login belum dapat diproses")
		return
	}
	token, expiresAt, err := api.tokens.Issue(user.ID, user.Role)
	if err != nil {
		api.logger.Printf("gagal membuat token sesi: %v", err)
		writeError(writer, http.StatusInternalServerError, "login belum dapat diproses")
		return
	}
	writeJSON(writer, http.StatusOK, map[string]any{
		"access_token": token,
		"token_type":   "Bearer",
		"expires_at":   expiresAt,
		"user":         user,
	})
}

// CATATAN PEMELIHARAAN: profil diambil ulang dari MongoDB agar perubahan nama,
// peran, status, dan waktu login tampil terbaru; jangan menjadikan claims JWT
// sebagai sumber data profil.
func (api *API) me(writer http.ResponseWriter, request *http.Request) {
	claims := claimsFromContext(request.Context())
	user, err := api.store.FindByID(request.Context(), claims.UserID)
	if err != nil {
		writeStoreError(api.logger, writer, err)
		return
	}
	if !user.IsActive {
		writeError(writer, http.StatusUnauthorized, "akun tidak aktif")
		return
	}
	writeJSON(writer, http.StatusOK, user)
}

// CATATAN PEMELIHARAAN: kata sandi lama diperlukan untuk membuktikan pemilik
// sesi; API hanya menerima kata sandi baru, bukan hash dari klien.
type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// CATATAN PEMELIHARAAN: perubahan hanya untuk akun dari token, memverifikasi
// kata sandi saat ini, lalu menyimpan hash Argon2id. Token lama tidak dicabut
// dan tetap berlaku sampai 15 menit; perubahan skema sesi perlu meninjau ini.
func (api *API) changePassword(writer http.ResponseWriter, request *http.Request) {
	var input changePasswordRequest
	if !decodeJSON(writer, request, &input) {
		return
	}
	if input.CurrentPassword == "" || !validPassword(input.NewPassword) {
		writeError(writer, http.StatusBadRequest, "kata sandi baru harus 12–128 karakter")
		return
	}
	claims := claimsFromContext(request.Context())
	user, err := api.store.FindByID(request.Context(), claims.UserID)
	if err != nil {
		writeStoreError(api.logger, writer, err)
		return
	}
	passwordMatches, err := api.verifyPassword(
		request.Context(),
		user.PasswordHash,
		input.CurrentPassword,
	)
	if err != nil {
		api.logger.Printf("verifikasi kata sandi gagal diproses: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "kata sandi belum dapat diubah")
		return
	}
	if !user.IsActive || !passwordMatches {
		writeError(writer, http.StatusUnauthorized, "kata sandi saat ini tidak valid")
		return
	}
	passwordHash, err := api.hashPassword(request.Context(), input.NewPassword)
	if err != nil {
		api.logger.Printf("gagal membuat hash kata sandi: %v", err)
		writeError(writer, http.StatusInternalServerError, "kata sandi belum dapat diubah")
		return
	}
	if err := api.store.UpdatePassword(request.Context(), user.ID, passwordHash); err != nil {
		api.logger.Printf("gagal menyimpan kata sandi baru: %v", err)
		writeError(writer, http.StatusInternalServerError, "kata sandi belum dapat diubah")
		return
	}
	writer.WriteHeader(http.StatusNoContent)
}

// CATATAN PEMELIHARAAN: panjang dihitung dalam rune agar pesan kebijakan sesuai
// karakter Unicode; samakan batas ini dengan bootstrap dan pembuatan pengguna.
func validPassword(value string) bool {
	return utf8.RuneCountInString(value) >= 12 &&
		utf8.RuneCountInString(value) <= 128
}
