package service

import (
	"context"

	"github.com/ArminDashti/lexmora-api/internal/domain"
	"github.com/ArminDashti/lexmora-api/internal/repository"
)

type SettingsService struct {
	settingsRepo *repository.SettingsRepository
}

func NewSettingsService(settingsRepo *repository.SettingsRepository) *SettingsService {
	return &SettingsService{settingsRepo: settingsRepo}
}

func (s *SettingsService) Get(ctx context.Context) (*domain.AppSettings, error) {
	return s.settingsRepo.Get(ctx)
}

func (s *SettingsService) Update(ctx context.Context, apiKey, modelName *string) (*domain.AppSettings, error) {
	return s.settingsRepo.Update(ctx, apiKey, modelName)
}

func (s *SettingsService) ClearAllData(ctx context.Context) error {
	return s.settingsRepo.ClearAllData(ctx)
}
