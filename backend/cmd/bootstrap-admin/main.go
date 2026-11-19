package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"golang.org/x/term"

	"inventaris_sederhana/backend/internal/auth"
	"inventaris_sederhana/backend/internal/config"
	"inventaris_sederhana/backend/internal/storage"
	"inventaris_sederhana/backend/internal/users"
)

// Hash ini hanya dipakai untuk mengganti akun admin statis dari database mockup lama.
const legacySeedHash = "$argon2id$v=19$m=65536,t=3,p=1$ds2d09GyLMuwxhRiSFY1cQ$su1rGtz4tGRuIkuCK5e3NsESgKDgIUsN0fMuxw9Bp0M"

var usernamePattern = regexp.MustCompile(`^[a-z0-9._-]{3,64}$`)

// CATATAN PEMELIHARAAN: command ini menyiapkan admin dari terminal lokal,
// bukan endpoint publik. Kata sandi tidak ditampilkan; jangan menggantinya
// dengan argumen command line atau log karena keduanya dapat terekspos.
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// CATATAN PEMELIHARAAN: nama/username divalidasi sebelum DB dibuka, lalu
// password dan konfirmasi dibaca tersembunyi, di-hash, dan diberikan ke
// BootstrapAdmin. Perintah hanya mengganti hash seed lama yang cocok persis
// atau membuat akun jika belum ada admin aktif.
func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Nama lengkap admin: ")
	fullName, err := reader.ReadString('\n')
	if err != nil {
		return errors.New("gagal membaca nama admin")
	}
	fullName = strings.TrimSpace(fullName)
	if fullName == "" || len([]rune(fullName)) > 200 {
		return errors.New("nama admin wajib diisi (maksimal 200 karakter)")
	}
	fmt.Print("Username admin [admin]: ")
	username, err := reader.ReadString('\n')
	if err != nil {
		return errors.New("gagal membaca username")
	}
	username = strings.ToLower(strings.TrimSpace(username))
	if username == "" {
		username = "admin"
	}
	if !usernamePattern.MatchString(username) {
		return errors.New("username harus 3–64 karakter dan hanya memakai huruf kecil, angka, titik, garis bawah, atau tanda hubung")
	}
	fmt.Print("Kata sandi admin (minimal 12 karakter): ")
	password, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Println()
	if err != nil {
		return errors.New("masukkan kata sandi melalui terminal interaktif")
	}
	fmt.Print("Ulangi kata sandi: ")
	confirmation, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Println()
	if err != nil {
		return errors.New("gagal membaca konfirmasi kata sandi")
	}
	if string(password) != string(confirmation) {
		return errors.New("konfirmasi kata sandi tidak cocok")
	}
	if len([]rune(string(password))) < 12 || len([]rune(string(password))) > 128 {
		return errors.New("kata sandi harus berisi 12–128 karakter")
	}
	passwordHash, err := auth.HashPassword(string(password))
	if err != nil {
		return fmt.Errorf("hash kata sandi: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	store, err := storage.Connect(ctx, cfg.MongoURI, cfg.DatabaseName)
	if err != nil {
		return err
	}
	defer store.Close(context.Background())
	now := time.Now().UTC()
	err = store.BootstrapAdmin(ctx, users.User{
		Username:     username,
		FullName:     fullName,
		PasswordHash: passwordHash,
		Role:         "admin",
		IsActive:     true,
		CreatedAt:    now,
		UpdatedAt:    &now,
	}, legacySeedHash)
	if err != nil {
		return err
	}
	fmt.Println("Akun admin berhasil disiapkan.")
	return nil
}
