package service

import (
	"context"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/ArminDashti/lexmora-api/internal/domain"
	"github.com/ArminDashti/lexmora-api/internal/repository"
)

type TransformRequest struct {
	Operation string `json:"operation"`
	Text      string `json:"text"`
	Text1     string `json:"text1"`
	Text2     string `json:"text2"`
	Direction string `json:"direction"`
	Mode      string `json:"mode"`
	MovieName string `json:"movie_name"`
	Language  string `json:"language"`
	Style     string `json:"style"`
}

type TransformService struct {
	historyRepo     *repository.HistoryRepository
	settingsService *SettingsService
	instructionSvc  *InstructionService
	openRouter      *OpenRouterClient
}

func NewTransformService(
	historyRepo *repository.HistoryRepository,
	settingsService *SettingsService,
	instructionSvc *InstructionService,
	openRouter *OpenRouterClient,
) *TransformService {
	return &TransformService{
		historyRepo:     historyRepo,
		settingsService: settingsService,
		instructionSvc:  instructionSvc,
		openRouter:      openRouter,
	}
}

func (s *TransformService) Transform(ctx context.Context, req TransformRequest) (*domain.TransformResult, error) {
	op := strings.ToLower(strings.TrimSpace(req.Operation))
	var inputText string
	if op == "compare" {
		text1 := strings.TrimSpace(req.Text1)
		text2 := strings.TrimSpace(req.Text2)
		if text1 == "" || text2 == "" {
			return nil, fmt.Errorf("text1 and text2 are required")
		}
		inputText = text1 + " vs " + text2
	} else {
		inputText = strings.TrimSpace(req.Text)
		if inputText == "" {
			return nil, fmt.Errorf("text is required")
		}
	}

	historyType, instructionKey, userText, metadata, err := s.resolveTransform(ctx, req, inputText)
	if err != nil {
		return nil, err
	}

	settings, err := s.settingsService.Get(ctx)
	if err != nil {
		return nil, err
	}

	systemPrompt, err := s.instructionSvc.BuildPrompt(ctx, instructionKey)
	if err != nil {
		return nil, err
	}

	result, err := s.openRouter.Complete(ctx, settings.OpenRouterAPIKey, settings.ModelName, systemPrompt, userText)
	if err != nil {
		return nil, err
	}

	record := domain.HistoryRecord{
		Type:           historyType,
		InputText:      inputText,
		ResultText:     result,
		Model:          settings.ModelName,
		InstructionKey: instructionKey,
		Metadata:       repository.MetadataJSON(metadata),
	}

	saved, err := s.historyRepo.Create(ctx, record)
	if err != nil {
		return nil, err
	}

	return &domain.TransformResult{
		ID:             saved.ID,
		Type:           saved.Type,
		TypeDisplay:    saved.TypeDisplay,
		InputText:      saved.InputText,
		ResultText:     saved.ResultText,
		Model:          saved.Model,
		InstructionKey: saved.InstructionKey,
		CreatedAt:      saved.CreatedAt,
		FormattedDate:  saved.FormattedDate,
	}, nil
}

func (s *TransformService) resolveTransform(ctx context.Context, req TransformRequest, text string) (domain.HistoryType, string, string, map[string]string, error) {
	op := strings.ToLower(strings.TrimSpace(req.Operation))
	metadata := map[string]string{}

	switch op {
	case "translate":
		dir := strings.ToLower(strings.TrimSpace(req.Direction))
		mode := normalizeSlug(req.Mode)
		if mode == "" {
			return "", "", "", nil, fmt.Errorf("invalid translate mode: %s", req.Mode)
		}
		var key string
		var historyType domain.HistoryType
		switch dir {
		case "en-fa":
			key = "en-to-fa-" + mode
			historyType = domain.HistoryTypeEnFa
		case "fa-en":
			key = "fa-to-en-" + mode
			historyType = domain.HistoryTypeFaEn
		default:
			return "", "", "", nil, fmt.Errorf("invalid translate direction: %s", req.Direction)
		}
		if err := s.requireInstruction(ctx, key); err != nil {
			return "", "", "", nil, err
		}
		if mode == "movie" {
			movie := strings.TrimSpace(req.MovieName)
			if movie == "" {
				return "", "", "", nil, fmt.Errorf("movie name is required for movie mode")
			}
			metadata["movie_name"] = movie
			return historyType, key, fmt.Sprintf("Movie: %s\n\n%s", movie, text), metadata, nil
		}
		return historyType, key, text, metadata, nil

	case "simplify":
		key := "simplify-en"
		if err := s.requireInstruction(ctx, key); err != nil {
			return "", "", "", nil, err
		}
		return domain.HistoryTypeSimplify, key, text, metadata, nil

	case "term":
		lang := strings.ToLower(strings.TrimSpace(req.Language))
		style := normalizeSlug(req.Style)
		if style == "" {
			return "", "", "", nil, fmt.Errorf("invalid term style: %s", req.Style)
		}
		key := "term-for-" + style
		if err := s.requireInstruction(ctx, key); err != nil {
			return "", "", "", nil, err
		}
		switch lang {
		case "en":
			return domain.HistoryTypeTermEn, key, "Find an English term for this description:\n\n" + text, metadata, nil
		case "fa":
			return domain.HistoryTypeTermFa, key, "Find a Persian term for this description:\n\n" + text, metadata, nil
		case "":
			// Language optional: instruction detects from input (legacy UI omitted language).
			return domain.HistoryTypeTermEn, key, text, metadata, nil
		default:
			return "", "", "", nil, fmt.Errorf("invalid term language: %s", req.Language)
		}

	case "refine":
		style := normalizeSlug(req.Style)
		if style == "" {
			return "", "", "", nil, fmt.Errorf("invalid refine style: %s", req.Style)
		}
		key := "refine-to-" + style
		if err := s.requireInstruction(ctx, key); err != nil {
			return "", "", "", nil, err
		}
		return domain.HistoryTypeRefine, key, text, metadata, nil

	case "symptoms":
		key := "symptoms"
		if err := s.requireInstruction(ctx, key); err != nil {
			return "", "", "", nil, err
		}
		return domain.HistoryTypeSymptoms, key, text, metadata, nil

	case "compare":
		lang := strings.ToLower(strings.TrimSpace(req.Language))
		if lang == "" {
			lang = "en"
		}
		text1 := strings.TrimSpace(req.Text1)
		text2 := strings.TrimSpace(req.Text2)
		metadata["text1"] = text1
		metadata["text2"] = text2
		metadata["language"] = lang
		key := "compare-" + lang
		if err := s.requireInstruction(ctx, key); err != nil {
			return "", "", "", nil, err
		}
		userMsg := fmt.Sprintf("Compare these two words or phrases:\n\n1: %s\n2: %s", text1, text2)
		switch lang {
		case "en":
			return domain.HistoryTypeCompareEn, key, userMsg, metadata, nil
		case "fa":
			return domain.HistoryTypeCompareFa, key, userMsg, metadata, nil
		default:
			return "", "", "", nil, fmt.Errorf("invalid compare language: %s", req.Language)
		}

	default:
		return "", "", "", nil, fmt.Errorf("invalid operation: %s", req.Operation)
	}
}

func (s *TransformService) requireInstruction(ctx context.Context, key string) error {
	if _, err := s.instructionSvc.Get(ctx, key); err != nil {
		return fmt.Errorf("instruction not found for key %s", key)
	}
	return nil
}

var slugPattern = regexp.MustCompile(`^[a-z0-9]+(?:-[a-z0-9]+)*$`)

func normalizeSlug(value string) string {
	s := strings.ToLower(strings.TrimSpace(value))
	s = strings.ReplaceAll(s, "_", "-")
	s = strings.Join(strings.Fields(s), "-")
	if !slugPattern.MatchString(s) {
		return ""
	}
	return s
}

func titleFromSlug(slug string) string {
	parts := strings.Split(slug, "-")
	for i, p := range parts {
		if p == "" {
			continue
		}
		r := []rune(p)
		r[0] = unicode.ToUpper(r[0])
		parts[i] = string(r)
	}
	return strings.Join(parts, " ")
}

// --- Transform options catalog (derived from instruction keys) ---

type OptionItem struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

type DirectionOption struct {
	Value string       `json:"value"`
	Label string       `json:"label"`
	Modes []OptionItem `json:"modes"`
}

type OperationOption struct {
	Value      string            `json:"value"`
	Label      string            `json:"label"`
	Directions []DirectionOption `json:"directions,omitempty"`
	Styles     []OptionItem      `json:"styles,omitempty"`
	Languages  []OptionItem      `json:"languages,omitempty"`
}

type TransformOptions struct {
	Operations []OperationOption `json:"operations"`
}

func (s *TransformService) GetOptions(ctx context.Context) (*TransformOptions, error) {
	items, err := s.instructionSvc.List(ctx)
	if err != nil {
		return nil, err
	}

	enFaModes := map[string]struct{}{}
	faEnModes := map[string]struct{}{}
	refineStyles := map[string]struct{}{}
	termStyles := map[string]struct{}{}
	compareLangs := map[string]struct{}{}
	hasSimplify := false
	hasSymptoms := false

	for _, item := range items {
		key := item.Key
		switch {
		case strings.HasPrefix(key, "en-to-fa-"):
			mode := strings.TrimPrefix(key, "en-to-fa-")
			if mode != "" {
				enFaModes[mode] = struct{}{}
			}
		case strings.HasPrefix(key, "fa-to-en-"):
			mode := strings.TrimPrefix(key, "fa-to-en-")
			if mode != "" {
				faEnModes[mode] = struct{}{}
			}
		case strings.HasPrefix(key, "refine-to-"):
			style := strings.TrimPrefix(key, "refine-to-")
			if style != "" {
				refineStyles[style] = struct{}{}
			}
		case strings.HasPrefix(key, "term-for-"):
			style := strings.TrimPrefix(key, "term-for-")
			if style != "" {
				termStyles[style] = struct{}{}
			}
		case strings.HasPrefix(key, "compare-"):
			lang := strings.TrimPrefix(key, "compare-")
			if lang != "" {
				compareLangs[lang] = struct{}{}
			}
		case key == "simplify-en":
			hasSimplify = true
		case key == "symptoms":
			hasSymptoms = true
		}
	}

	ops := make([]OperationOption, 0, 6)

	if len(enFaModes) > 0 || len(faEnModes) > 0 {
		dirs := make([]DirectionOption, 0, 2)
		if len(enFaModes) > 0 {
			dirs = append(dirs, DirectionOption{
				Value: "en-fa",
				Label: "English → Persian",
				Modes: sortedOptions(enFaModes),
			})
		}
		if len(faEnModes) > 0 {
			dirs = append(dirs, DirectionOption{
				Value: "fa-en",
				Label: "Persian → English",
				Modes: sortedOptions(faEnModes),
			})
		}
		ops = append(ops, OperationOption{
			Value:      "translate",
			Label:      "Translate",
			Directions: dirs,
		})
	}
	if hasSimplify {
		ops = append(ops, OperationOption{Value: "simplify", Label: "Simplify"})
	}
	if len(termStyles) > 0 {
		ops = append(ops, OperationOption{
			Value:  "term",
			Label:  "Term",
			Styles: sortedOptions(termStyles),
			Languages: []OptionItem{
				{Value: "en", Label: "English"},
				{Value: "fa", Label: "Persian"},
			},
		})
	}
	if len(refineStyles) > 0 {
		ops = append(ops, OperationOption{
			Value:  "refine",
			Label:  "Refine",
			Styles: sortedOptions(refineStyles),
		})
	}
	if hasSymptoms {
		ops = append(ops, OperationOption{Value: "symptoms", Label: "Symptoms"})
	}
	if len(compareLangs) > 0 {
		ops = append(ops, OperationOption{
			Value:     "compare",
			Label:     "Compare",
			Languages: sortedLanguageOptions(compareLangs),
		})
	}

	return &TransformOptions{Operations: ops}, nil
}

func sortedOptions(set map[string]struct{}) []OptionItem {
	keys := make([]string, 0, len(set))
	for k := range set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]OptionItem, 0, len(keys))
	for _, k := range keys {
		out = append(out, OptionItem{Value: k, Label: titleFromSlug(k)})
	}
	return out
}

func sortedLanguageOptions(set map[string]struct{}) []OptionItem {
	keys := make([]string, 0, len(set))
	for k := range set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	out := make([]OptionItem, 0, len(keys))
	for _, k := range keys {
		label := titleFromSlug(k)
		switch k {
		case "en":
			label = "English"
		case "fa":
			label = "Persian"
		}
		out = append(out, OptionItem{Value: k, Label: label})
	}
	return out
}

// --- Create instruction from structured operation fields ---

type CreateInstructionRequest struct {
	Operation string `json:"operation"`
	Direction string `json:"direction"`
	Mode      string `json:"mode"`
	Style     string `json:"style"`
	Language  string `json:"language"`
	Content   string `json:"content"`
}

func (s *InstructionService) CreateFromOperation(ctx context.Context, req CreateInstructionRequest) (*domain.Instruction, error) {
	key, err := buildInstructionKey(req)
	if err != nil {
		return nil, err
	}

	content := strings.TrimSpace(req.Content)
	if content == "" {
		content = defaultInstructionContent(key)
	}
	return s.repo.Upsert(ctx, key, content)
}

func buildInstructionKey(req CreateInstructionRequest) (string, error) {
	op := strings.ToLower(strings.TrimSpace(req.Operation))
	switch op {
	case "translate":
		dir := strings.ToLower(strings.TrimSpace(req.Direction))
		mode := normalizeSlug(req.Mode)
		if mode == "" {
			return "", fmt.Errorf("invalid mode: %s", req.Mode)
		}
		switch dir {
		case "en-fa":
			return "en-to-fa-" + mode, nil
		case "fa-en":
			return "fa-to-en-" + mode, nil
		default:
			return "", fmt.Errorf("invalid direction: %s", req.Direction)
		}
	case "refine":
		style := normalizeSlug(req.Style)
		if style == "" {
			style = normalizeSlug(req.Mode)
		}
		if style == "" {
			return "", fmt.Errorf("invalid style: %s", req.Style)
		}
		return "refine-to-" + style, nil
	case "term":
		style := normalizeSlug(req.Style)
		if style == "" {
			style = normalizeSlug(req.Mode)
		}
		if style == "" {
			return "", fmt.Errorf("invalid style: %s", req.Style)
		}
		return "term-for-" + style, nil
	case "simplify":
		return "simplify-en", nil
	case "symptoms":
		return "symptoms", nil
	case "compare":
		lang := strings.ToLower(strings.TrimSpace(req.Language))
		if lang == "" {
			lang = normalizeSlug(req.Mode)
		}
		if lang != "en" && lang != "fa" {
			return "", fmt.Errorf("invalid language: %s", req.Language)
		}
		return "compare-" + lang, nil
	default:
		return "", fmt.Errorf("invalid operation: %s", req.Operation)
	}
}

type HistoryService struct {
	repo *repository.HistoryRepository
}

func NewHistoryService(repo *repository.HistoryRepository) *HistoryService {
	return &HistoryService{repo: repo}
}

func (s *HistoryService) List(ctx context.Context, filter repository.HistoryListFilter) ([]domain.HistoryRecord, error) {
	return s.repo.List(ctx, filter)
}

func (s *HistoryService) Get(ctx context.Context, id string) (*domain.HistoryRecord, error) {
	uid, err := uuid.Parse(id)
	if err != nil {
		return nil, fmt.Errorf("invalid id")
	}
	return s.repo.GetByID(ctx, uid)
}

func (s *HistoryService) Delete(ctx context.Context, id string) error {
	uid, err := uuid.Parse(id)
	if err != nil {
		return fmt.Errorf("invalid id")
	}
	return s.repo.Delete(ctx, uid)
}

type StatsService struct {
	repo *repository.HistoryRepository
}

func NewStatsService(repo *repository.HistoryRepository) *StatsService {
	return &StatsService{repo: repo}
}

func (s *StatsService) Get(ctx context.Context) (*domain.StatsResponse, error) {
	now := time.Now()
	startToday := startOfDay(now)
	startYesterday := startToday.AddDate(0, 0, -1)
	startWeek := startToday.AddDate(0, 0, -6)
	startMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())

	today, err := s.repo.CountByPeriod(ctx, &startToday, nil)
	if err != nil {
		return nil, err
	}
	yesterday, err := s.repo.CountByPeriod(ctx, &startYesterday, &startToday)
	if err != nil {
		return nil, err
	}
	week, err := s.repo.CountByPeriod(ctx, &startWeek, nil)
	if err != nil {
		return nil, err
	}
	month, err := s.repo.CountByPeriod(ctx, &startMonth, nil)
	if err != nil {
		return nil, err
	}
	allTime, err := s.repo.CountByPeriod(ctx, nil, nil)
	if err != nil {
		return nil, err
	}

	return &domain.StatsResponse{
		Today:     today,
		Yesterday: yesterday,
		Week:      week,
		Month:     month,
		AllTime:   allTime,
	}, nil
}

func startOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}
