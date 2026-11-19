package storage

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"inventaris_sederhana/backend/internal/maintenance"
)

type maintenanceDocument struct {
	ID          string     `bson:"_id"`
	AssetID     string     `bson:"asset_id"`
	ReportedBy  string     `bson:"reported_by"`
	Status      string     `bson:"status"`
	Description string     `bson:"description"`
	Cost        float64    `bson:"cost"`
	ReportedAt  time.Time  `bson:"reported_at"`
	ClosedAt    *time.Time `bson:"closed_at"`
}

// CATATAN PEMELIHARAAN: laporan menyimpan ID aset dan pelapor, bukan label
// dari browser; label ditautkan kembali saat dibaca agar selalu mengikuti data
// master. Status dan biaya diperbarui dengan filter status lama supaya dua
// petugas tidak dapat menyelesaikan transisi yang sama secara bersamaan.
func (store *Mongo) CountMaintenance(ctx context.Context) (int64, error) {
	total, err := store.db.Collection("maintenance_records").CountDocuments(ctx, bson.D{})
	if err != nil {
		return 0, fmt.Errorf("hitung laporan pemeliharaan: %w", err)
	}
	return total, nil
}

func (store *Mongo) ListMaintenance(ctx context.Context, skip, limit int64) ([]maintenance.Record, error) {
	cursor, err := store.db.Collection("maintenance_records").Find(ctx, bson.D{}, options.Find().
		SetSort(bson.D{{Key: "reported_at", Value: -1}, {Key: "_id", Value: 1}}).
		SetSkip(skip).SetLimit(limit))
	if err != nil {
		return nil, fmt.Errorf("ambil halaman pemeliharaan: %w", err)
	}
	defer cursor.Close(ctx)
	documents := make([]maintenanceDocument, 0)
	if err := cursor.All(ctx, &documents); err != nil {
		return nil, fmt.Errorf("baca halaman pemeliharaan: %w", err)
	}
	return store.maintenanceRecords(ctx, documents)
}

func (store *Mongo) CreateMaintenance(ctx context.Context, input maintenance.CreateInput, actorID string) (maintenance.Record, error) {
	var asset assetDocument
	if err := store.db.Collection("assets").FindOne(ctx, bson.M{"_id": input.AssetID, "asset_status": "active"}).Decode(&asset); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return maintenance.Record{}, maintenance.ErrInvalidReference
		}
		return maintenance.Record{}, fmt.Errorf("validasi aset pemeliharaan: %w", err)
	}
	var actor inventoryUserDocument
	if err := store.db.Collection("users").FindOne(ctx, bson.M{"_id": actorID, "is_active": true}).Decode(&actor); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return maintenance.Record{}, maintenance.ErrInvalidReference
		}
		return maintenance.Record{}, fmt.Errorf("validasi pelapor pemeliharaan: %w", err)
	}
	now := time.Now().UTC()
	doc := maintenanceDocument{
		ID: uuid.NewString(), AssetID: asset.ID, ReportedBy: actorID,
		Status: "reported", Description: input.Description, Cost: 0, ReportedAt: now,
	}
	if _, err := store.db.Collection("maintenance_records").InsertOne(ctx, bson.M{
		"_id": doc.ID, "asset_id": doc.AssetID, "reported_by": doc.ReportedBy,
		"status": doc.Status, "description": doc.Description, "cost": doc.Cost,
		"reported_at": doc.ReportedAt, "closed_at": nil,
	}); err != nil {
		return maintenance.Record{}, fmt.Errorf("simpan laporan pemeliharaan: %w", err)
	}
	records, err := store.maintenanceRecords(ctx, []maintenanceDocument{doc})
	if err != nil {
		return maintenance.Record{}, err
	}
	return records[0], nil
}

func (store *Mongo) UpdateMaintenance(ctx context.Context, id string, input maintenance.UpdateInput) (maintenance.Record, error) {
	collection := store.db.Collection("maintenance_records")
	var current maintenanceDocument
	if err := collection.FindOne(ctx, bson.M{"_id": id}).Decode(&current); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return maintenance.Record{}, maintenance.ErrNotFound
		}
		return maintenance.Record{}, fmt.Errorf("baca laporan sebelum perubahan: %w", err)
	}
	if !maintenance.CanTransition(current.Status, input.Status) {
		return maintenance.Record{}, maintenance.ErrInvalidState
	}
	now := time.Now().UTC()
	var closedAt *time.Time
	if input.Status == "completed" || input.Status == "cancelled" {
		closedAt = &now
	}
	cost := current.Cost
	if input.Status == "completed" {
		cost = input.Cost
	}
	result, err := collection.UpdateOne(ctx,
		bson.M{"_id": id, "status": current.Status},
		bson.M{"$set": bson.M{"status": input.Status, "cost": cost, "closed_at": closedAt}},
	)
	if err != nil {
		return maintenance.Record{}, fmt.Errorf("perbarui status laporan pemeliharaan: %w", err)
	}
	if result.MatchedCount == 0 {
		return maintenance.Record{}, maintenance.ErrConcurrentEdit
	}
	var updated maintenanceDocument
	if err := collection.FindOne(ctx, bson.M{"_id": id}).Decode(&updated); err != nil {
		return maintenance.Record{}, fmt.Errorf("baca laporan setelah perubahan: %w", err)
	}
	records, err := store.maintenanceRecords(ctx, []maintenanceDocument{updated})
	if err != nil {
		return maintenance.Record{}, err
	}
	return records[0], nil
}

func (store *Mongo) maintenanceRecords(ctx context.Context, documents []maintenanceDocument) ([]maintenance.Record, error) {
	records := make([]maintenance.Record, 0, len(documents))
	for _, doc := range documents {
		var asset assetDocument
		if err := store.db.Collection("assets").FindOne(ctx, bson.M{"_id": doc.AssetID}).Decode(&asset); err != nil {
			return nil, fmt.Errorf("baca aset laporan pemeliharaan %s: %w", doc.ID, err)
		}
		var item inventoryItemDocument
		if err := store.db.Collection("items").FindOne(ctx, bson.M{"_id": asset.ItemID}).Decode(&item); err != nil {
			return nil, fmt.Errorf("baca nama aset laporan pemeliharaan %s: %w", doc.ID, err)
		}
		var actor inventoryUserDocument
		if err := store.db.Collection("users").FindOne(ctx, bson.M{"_id": doc.ReportedBy}).Decode(&actor); err != nil {
			return nil, fmt.Errorf("baca pelapor laporan pemeliharaan %s: %w", doc.ID, err)
		}
		records = append(records, maintenance.Record{
			ID: doc.ID, AssetID: doc.AssetID, AssetCode: asset.AssetCode,
			AssetName: item.Name, ReportedBy: actor.FullName, ReportedByID: doc.ReportedBy,
			Status: doc.Status, Description: doc.Description, Cost: doc.Cost,
			ReportedAt: doc.ReportedAt, ClosedAt: doc.ClosedAt,
		})
	}
	return records, nil
}
