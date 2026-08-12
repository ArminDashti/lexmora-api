package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/ArminDashti/lexmora-api/internal/domain"
)

type HistoryRepository struct {
	pool *pgxpool.Pool
}

func NewHistoryRepository(pool *pgxpool.Pool) *HistoryRepository {
	return &HistoryRepository{pool: pool}
}

type HistoryListFilter struct {
	SortBy    string
	SortOrder string
	Limit     int
	Offset    int
	Type      string
	From      *time.Time
	To        *time.Time
}

func (r *HistoryRepository) Create(ctx context.Context, record domain.HistoryRecord) (*domain.HistoryRecord, error) {
	var metadata any
	if len(record.Metadata) > 0 {
		metadata = record.Metadata
	}

	var h domain.HistoryRecord
	var metaBytes []byte
	err := r.pool.QueryRow(ctx, `
		INSERT INTO history (type, input_text, result_text, model, instruction_key, metadata)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, type, input_text, result_text, model, instruction_key, metadata, created_at
	`, record.Type, record.InputText, record.ResultText, record.Model, record.InstructionKey, metadata).Scan(
		&h.ID, &h.Type, &h.InputText, &h.ResultText, &h.Model, &h.InstructionKey, &metaBytes, &h.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create history: %w", err)
	}
	h.Metadata = metaBytes
	enrichHistory(&h)
	return &h, nil
}

func (r *HistoryRepository) GetByID(ctx context.Context, id uuid.UUID) (*domain.HistoryRecord, error) {
	return r.scanOne(ctx, `SELECT id, type, input_text, result_text, model, instruction_key, metadata, created_at FROM history WHERE id = $1`, id)
}

func (r *HistoryRepository) List(ctx context.Context, filter HistoryListFilter) ([]domain.HistoryRecord, error) {
	col := "created_at"
	switch strings.ToLower(filter.SortBy) {
	case "type":
		col = "type"
	case "model":
		col = "model"
	case "datetime", "created_at":
		col = "created_at"
	}

	order := "DESC"
	if strings.ToLower(filter.SortOrder) == "asc" {
		order = "ASC"
	}

	limit := filter.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}

	where := []string{"1=1"}
	args := []any{}
	argN := 1

	if t := strings.TrimSpace(filter.Type); t != "" {
		where = append(where, fmt.Sprintf("type = $%d", argN))
		args = append(args, t)
		argN++
	}
	if filter.From != nil {
		where = append(where, fmt.Sprintf("created_at >= $%d", argN))
		args = append(args, *filter.From)
		argN++
	}
	if filter.To != nil {
		where = append(where, fmt.Sprintf("created_at < $%d", argN))
		args = append(args, *filter.To)
		argN++
	}

	args = append(args, limit, filter.Offset)
	limitIdx := argN
	offsetIdx := argN + 1

	query := fmt.Sprintf(`
		SELECT id, type, input_text, result_text, model, instruction_key, metadata, created_at
		FROM history
		WHERE %s
		ORDER BY %s %s
		LIMIT $%d OFFSET $%d
	`, strings.Join(where, " AND "), col, order, limitIdx, offsetIdx)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list history: %w", err)
	}
	defer rows.Close()

	var items []domain.HistoryRecord
	for rows.Next() {
		var h domain.HistoryRecord
		var metaBytes []byte
		if err := rows.Scan(&h.ID, &h.Type, &h.InputText, &h.ResultText, &h.Model, &h.InstructionKey, &metaBytes, &h.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan history: %w", err)
		}
		h.Metadata = metaBytes
		enrichHistory(&h)
		items = append(items, h)
	}
	return items, rows.Err()
}

func (r *HistoryRepository) Delete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM history WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete history: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *HistoryRepository) ClearAll(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM history`)
	return err
}

type statsRow struct {
	Type  domain.HistoryType
	Count int
}

func (r *HistoryRepository) CountByPeriod(ctx context.Context, since, until *time.Time) (domain.StatsBucket, error) {
	query := `SELECT type, COUNT(*) FROM history WHERE 1=1`
	args := []any{}
	argN := 1
	if since != nil {
		query += fmt.Sprintf(" AND created_at >= $%d", argN)
		args = append(args, *since)
		argN++
	}
	if until != nil {
		query += fmt.Sprintf(" AND created_at < $%d", argN)
		args = append(args, *until)
	}
	query += ` GROUP BY type`

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return domain.StatsBucket{}, fmt.Errorf("count stats: %w", err)
	}
	defer rows.Close()

	bucket := domain.StatsBucket{}
	for rows.Next() {
		var row statsRow
		if err := rows.Scan(&row.Type, &row.Count); err != nil {
			return domain.StatsBucket{}, err
		}
		addToBucket(&bucket, row.Type, row.Count)
	}
	bucket.Total = bucket.Simplify + bucket.EnFa + bucket.FaEn + bucket.Term + bucket.Refine + bucket.Symptoms + bucket.Compare + bucket.Grammar
	return bucket, rows.Err()
}

func (r *HistoryRepository) Count(ctx context.Context, filter HistoryListFilter) (int, error) {
	where := []string{"1=1"}
	args := []any{}
	argN := 1

	if t := strings.TrimSpace(filter.Type); t != "" {
		where = append(where, fmt.Sprintf("type = $%d", argN))
		args = append(args, t)
		argN++
	}
	if filter.From != nil {
		where = append(where, fmt.Sprintf("created_at >= $%d", argN))
		args = append(args, *filter.From)
		argN++
	}
	if filter.To != nil {
		where = append(where, fmt.Sprintf("created_at < $%d", argN))
		args = append(args, *filter.To)
		argN++
	}

	query := fmt.Sprintf(`SELECT COUNT(*) FROM history WHERE %s`, strings.Join(where, " AND "))
	var total int
	if err := r.pool.QueryRow(ctx, query, args...).Scan(&total); err != nil {
		return 0, fmt.Errorf("count history: %w", err)
	}
	return total, nil
}

func addToBucket(b *domain.StatsBucket, t domain.HistoryType, count int) {
	switch t {
	case domain.HistoryTypeSimplify:
		b.Simplify += count
	case domain.HistoryTypeEnFa:
		b.EnFa += count
	case domain.HistoryTypeFaEn:
		b.FaEn += count
	case domain.HistoryTypeTermEn, domain.HistoryTypeTermFa:
		b.Term += count
	case domain.HistoryTypeRefine:
		b.Refine += count
	case domain.HistoryTypeSymptoms:
		b.Symptoms += count
	case domain.HistoryTypeCompareEn, domain.HistoryTypeCompareFa:
		b.Compare += count
	case domain.HistoryTypeGrammarEn, domain.HistoryTypeGrammarFa:
		b.Grammar += count
	}
}

func (r *HistoryRepository) scanOne(ctx context.Context, query string, args ...any) (*domain.HistoryRecord, error) {
	var h domain.HistoryRecord
	var metaBytes []byte
	err := r.pool.QueryRow(ctx, query, args...).Scan(
		&h.ID, &h.Type, &h.InputText, &h.ResultText, &h.Model, &h.InstructionKey, &metaBytes, &h.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan history: %w", err)
	}
	h.Metadata = metaBytes
	enrichHistory(&h)
	return &h, nil
}

func enrichHistory(h *domain.HistoryRecord) {
	h.TypeDisplay = h.Type.DisplayName()
	h.FormattedDate = domain.FormatDateTime(h.CreatedAt)
}

func MetadataJSON(data map[string]string) json.RawMessage {
	if len(data) == 0 {
		return nil
	}
	b, _ := json.Marshal(data)
	return b
}
