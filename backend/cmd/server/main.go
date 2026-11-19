package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"inventaris_sederhana/backend/internal/config"
	"inventaris_sederhana/backend/internal/httpapi"
	"inventaris_sederhana/backend/internal/storage"
)

// CATATAN PEMELIHARAAN: main hanya mengakhiri proses jika run gagal; detail
// startup/shutdown berada di run agar alur layanan dapat diuji terpisah.
func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

// CATATAN PEMELIHARAAN: run memvalidasi env, membuka koneksi MongoDB, memasang
// timeout HTTP, lalu menutup server dengan graceful shutdown saat sinyal OS
// diterima. Ubah startup dependencies dan readiness check di sini.
func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	connectCtx, cancelConnect := context.WithTimeout(context.Background(), 10*time.Second)
	store, err := storage.Connect(connectCtx, cfg.MongoURI, cfg.DatabaseName)
	cancelConnect()
	if err != nil {
		return err
	}
	defer func() {
		closeCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := store.Close(closeCtx); err != nil {
			log.Printf("menutup koneksi MongoDB: %v", err)
		}
	}()

	api, err := httpapi.New(store, store, cfg.JWTSecret, cfg.CORSOrigins, log.Default())
	if err != nil {
		return err
	}
	server := &http.Server{
		Addr:              cfg.HTTPAddress,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("API berjalan di %s", cfg.HTTPAddress)
		serverErrors <- server.ListenAndServe()
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	select {
	case err := <-serverErrors:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-signals:
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}
