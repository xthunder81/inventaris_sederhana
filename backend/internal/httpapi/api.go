package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"inventaris_sederhana/backend/internal/auth"
	"inventaris_sederhana/backend/internal/users"
)

// CATATAN PEMELIHARAAN: kontrak ini membatasi handler ke operasi akun yang
// dibutuhkan API; implementasi Mongo harus mempertahankan arti sentinel error
// ErrNotFound dan ErrConflict agar status HTTP tetap konsisten.
type UserStore interface {
	FindByUsername(context.Context, string) (users.User, error)
	FindByID(context.Context, string) (users.User, error)
	List(context.Context, int64, int64) ([]users.User, error)
	Count(context.Context) (int64, error)
	Create(context.Context, users.User) error
	Update(context.Context, string, users.Update) (users.User, error)
	UpdatePassword(context.Context, string, string) error
	UpdateLastLogin(context.Context, string, time.Time) error
	RecordLogin(context.Context, users.LoginEvent) error
}

// CATATAN PEMELIHARAAN: health check hanya membutuhkan ping, bukan detail driver
// Mongo, sehingga pengujian dapat memakai store palsu tanpa database.
type HealthStore interface {
	Ping(context.Context) error
}

// API menyimpan dependensi bersama untuk satu instance HTTP server.
type API struct {
	store             UserStore
	locationStore     LocationStore
	catalogStore      CatalogStore
	locationWrites    sync.Mutex
	inventoryStore    InventoryStore
	stockItemStore    StockItemStore
	inventoryWrites   sync.Mutex
	maintenanceStore  MaintenanceStore
	maintenanceWrites sync.Mutex
	movementStore     MovementStore
	movementWrites    sync.Mutex
	health            HealthStore
	tokens            *auth.TokenManager
	corsOrigins       map[string]struct{}
	dummyHash         string
	logger            *log.Logger
	hashSlots         chan struct{}
}

// CATATAN PEMELIHARAAN: hash dummy membuat login username tak dikenal tetap
// menjalankan Argon2id seperti username yang ada; hashSlots membatasi dua
// operasi hash/verifikasi bersamaan karena tiap operasi memakai RAM besar.
// Jika parameter Argon2id berubah, evaluasi batas concurrency pada server.
func New(store UserStore, health HealthStore, tokenSecret []byte, origins []string, logger *log.Logger) (*API, error) {
	dummyPassword := make([]byte, 32)
	if _, err := rand.Read(dummyPassword); err != nil {
		return nil, err
	}
	dummyHash, err := auth.HashPassword(base64.RawStdEncoding.EncodeToString(dummyPassword))
	if err != nil {
		return nil, err
	}
	allowedOrigins := make(map[string]struct{}, len(origins))
	for _, origin := range origins {
		allowedOrigins[origin] = struct{}{}
	}
	if logger == nil {
		logger = log.Default()
	}
	locationStore, _ := store.(LocationStore)
	catalogStore, _ := store.(CatalogStore)
	inventoryStore, _ := store.(InventoryStore)
	stockItemStore, _ := store.(StockItemStore)
	maintenanceStore, _ := store.(MaintenanceStore)
	movementStore, _ := store.(MovementStore)
	return &API{
		store:            store,
		locationStore:    locationStore,
		catalogStore:     catalogStore,
		inventoryStore:   inventoryStore,
		stockItemStore:   stockItemStore,
		maintenanceStore: maintenanceStore,
		movementStore:    movementStore,
		health:           health,
		tokens:           auth.NewTokenManager(tokenSecret),
		corsOrigins:      allowedOrigins,
		dummyHash:        dummyHash,
		logger:           logger,
		hashSlots:        make(chan struct{}, 2),
	}, nil
}

// CATATAN PEMELIHARAAN: seluruh endpoint terdaftar di sini supaya kebijakan
// auth/role tidak tersebar; endpoint data baru harus diberi middleware yang
// tepat dan ditambahkan ke dokumentasi README.
func (api *API) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", api.healthCheck)
	mux.HandleFunc("POST /api/v1/auth/login", api.login)
	mux.Handle("GET /api/v1/auth/me", api.requireAuth(http.HandlerFunc(api.me)))
	mux.Handle("POST /api/v1/auth/change-password", api.requireAuth(http.HandlerFunc(api.changePassword)))
	mux.Handle("GET /api/v1/users", api.requireRole("admin", http.HandlerFunc(api.listUsers)))
	mux.Handle("POST /api/v1/users", api.requireRole("admin", http.HandlerFunc(api.createUser)))
	mux.Handle("PATCH /api/v1/users/{id}", api.requireRole("admin", http.HandlerFunc(api.updateUser)))
	mux.Handle("GET /api/v1/locations", api.requireAuth(http.HandlerFunc(api.listLocations)))
	mux.Handle("POST /api/v1/locations", api.requireRole("admin", http.HandlerFunc(api.createLocation)))
	mux.Handle("PATCH /api/v1/locations/{id}", api.requireRole("admin", http.HandlerFunc(api.updateLocation)))
	mux.Handle("GET /api/v1/item-kinds", api.requireAuth(http.HandlerFunc(api.listItemKinds)))
	mux.Handle("POST /api/v1/item-kinds", api.requireRole("admin", http.HandlerFunc(api.createItemKind)))
	mux.Handle("PATCH /api/v1/item-kinds/{id}", api.requireRole("admin", http.HandlerFunc(api.updateItemKind)))
	mux.Handle("GET /api/v1/categories", api.requireAuth(http.HandlerFunc(api.listCategories)))
	mux.Handle("POST /api/v1/categories", api.requireRole("admin", http.HandlerFunc(api.createCategory)))
	mux.Handle("PATCH /api/v1/categories/{id}", api.requireRole("admin", http.HandlerFunc(api.updateCategory)))
	mux.Handle("GET /api/v1/assets", api.requireAuth(http.HandlerFunc(api.listAssets)))
	mux.Handle("POST /api/v1/assets", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.createAsset)))
	mux.Handle("PATCH /api/v1/assets/{id}/condition", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.changeAssetCondition)))
	mux.Handle("PATCH /api/v1/assets/{id}", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.updateAsset)))
	mux.Handle("PATCH /api/v1/assets/{id}/archive", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.archiveAsset)))
	mux.Handle("GET /api/v1/stock-items", api.requireAuth(http.HandlerFunc(api.listStockItems)))
	mux.Handle("POST /api/v1/stock-items", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.createStockItem)))
	mux.Handle("PATCH /api/v1/stock-items/{id}", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.updateStockItem)))
	mux.Handle("GET /api/v1/maintenance-records", api.requireAuth(http.HandlerFunc(api.listMaintenance)))
	mux.Handle("POST /api/v1/maintenance-records", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.createMaintenance)))
	mux.Handle("PATCH /api/v1/maintenance-records/{id}", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.updateMaintenance)))
	mux.Handle("GET /api/v1/movements", api.requireAuth(http.HandlerFunc(api.listMovements)))
	mux.Handle("POST /api/v1/movements", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.createMovement)))
	mux.Handle("PATCH /api/v1/movements/{id}/cancel", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.cancelMovement)))
	mux.Handle("PATCH /api/v1/movements/{id}/post", api.requireAnyRole([]string{"admin", "petugas"}, http.HandlerFunc(api.postMovement)))
	return api.cors(mux)
}

type contextKey string

const claimsContextKey contextKey = "auth-claims"

// CATATAN PEMELIHARAAN: nilai hanya disediakan requireAuth; jangan membaca
// claims dari request tanpa melewati middleware autentikasi terlebih dahulu.
func claimsFromContext(ctx context.Context) auth.Claims {
	claims, _ := ctx.Value(claimsContextKey).(auth.Claims)
	return claims
}

// CATATAN PEMELIHARAAN: selain memeriksa signature/expiry, middleware membaca
// akun terkini dari DB agar akun nonaktif atau peran yang dicabut langsung
// berlaku. Jika kelak memakai cache, tetapkan TTL/revocation yang tetap aman.
func (api *API) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		header := request.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(writer, http.StatusUnauthorized, "sesi tidak valid atau sudah berakhir")
			return
		}
		claims, err := api.tokens.Parse(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			writeError(writer, http.StatusUnauthorized, "sesi tidak valid atau sudah berakhir")
			return
		}
		user, err := api.store.FindByID(request.Context(), claims.UserID)
		if err != nil {
			if err == users.ErrNotFound {
				writeError(writer, http.StatusUnauthorized, "sesi tidak valid atau sudah berakhir")
				return
			}
			api.logger.Printf("gagal memeriksa status akun: %v", err)
			writeError(writer, http.StatusServiceUnavailable, "sesi belum dapat diverifikasi")
			return
		}
		if !user.IsActive {
			writeError(writer, http.StatusUnauthorized, "akun tidak aktif")
			return
		}
		claims.Role = user.Role
		next.ServeHTTP(writer, request.WithContext(
			context.WithValue(request.Context(), claimsContextKey, claims),
		))
	})
}

// CATATAN PEMELIHARAAN: peran yang dibandingkan berasal dari akun terkini,
// bukan hanya claim JWT; ubah pemetaan role di sini bila model otorisasi berubah.
func (api *API) requireRole(role string, next http.Handler) http.Handler {
	return api.requireAnyRole([]string{role}, next)
}

func (api *API) requireAnyRole(roles []string, next http.Handler) http.Handler {
	return api.requireAuth(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		role := claimsFromContext(request.Context()).Role
		for _, allowedRole := range roles {
			if role == allowedRole {
				next.ServeHTTP(writer, request)
				return
			}
		}
		writeError(writer, http.StatusForbidden, "akses tidak diizinkan")
	}))
}

// CATATAN PEMELIHARAAN: origin harus cocok persis dengan allowlist; jangan
// mengizinkan "*" untuk mempermudah development. Cookie/credential CORS tidak
// dipakai karena autentikasi API memakai bearer token.
func (api *API) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		origin := request.Header.Get("Origin")
		if origin != "" {
			if _, allowed := api.corsOrigins[origin]; !allowed {
				writeError(writer, http.StatusForbidden, "origin tidak diizinkan")
				return
			}
			writer.Header().Set("Access-Control-Allow-Origin", origin)
			writer.Header().Set("Vary", "Origin")
			writer.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")
		}
		if request.Method == http.MethodOptions {
			writer.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(writer, request)
	})
}

// CATATAN PEMELIHARAAN: endpoint sehat hanya jika MongoDB dapat diping; response
// tidak mengungkap URI atau detail error, sedangkan detail teknis masuk log.
func (api *API) healthCheck(writer http.ResponseWriter, request *http.Request) {
	if err := api.health.Ping(request.Context()); err != nil {
		api.logger.Printf("health check MongoDB gagal: %v", err)
		writeError(writer, http.StatusServiceUnavailable, "database tidak tersedia")
		return
	}
	writeJSON(writer, http.StatusOK, map[string]string{"status": "ok"})
}

// CATATAN PEMELIHARAAN: batas page dan page_size mencegah query berukuran
// berlebihan; bila pagination diubah ke cursor, sesuaikan response dan UI
// pengguna, bukan hanya query Mongo.
func parsePage(request *http.Request) (int64, int64, error) {
	page := int64(1)
	pageSize := int64(20)
	if value := request.URL.Query().Get("page"); value != "" {
		parsed, err := strconv.ParseInt(value, 10, 64)
		if err != nil || parsed < 1 || parsed > 1_000_000 {
			return 0, 0, errors.New("page harus antara 1 dan 1000000")
		}
		page = parsed
	}
	if value := request.URL.Query().Get("page_size"); value != "" {
		parsed, err := strconv.ParseInt(value, 10, 64)
		if err != nil || parsed < 1 || parsed > 100 {
			return 0, 0, errors.New("page_size harus antara 1 dan 100")
		}
		pageSize = parsed
	}
	return page, pageSize, nil
}

// CATATAN PEMELIHARAAN: semaphore ini membatasi konsumsi RAM Argon2id dan
// menghormati pembatalan request; ubah kapasitas hanya setelah uji beban.
func (api *API) hashPassword(ctx context.Context, password string) (string, error) {
	select {
	case api.hashSlots <- struct{}{}:
		defer func() { <-api.hashSlots }()
		return auth.HashPassword(password)
	case <-ctx.Done():
		return "", ctx.Err()
	}
}

// CATATAN PEMELIHARAAN: verifikasi dibatasi semaphore yang sama dengan hash
// baru supaya login paralel tidak menghabiskan memori server.
func (api *API) verifyPassword(ctx context.Context, encodedHash, password string) (bool, error) {
	select {
	case api.hashSlots <- struct{}{}:
		defer func() { <-api.hashSlots }()
		return auth.VerifyPassword(encodedHash, password), nil
	case <-ctx.Done():
		return false, ctx.Err()
	}
}
