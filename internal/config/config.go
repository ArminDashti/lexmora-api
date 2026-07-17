package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	Port            string
	JWTSecret       string
	DatabaseURL     string
	StaticDir       string
	CorsOrigins     []string
	DefaultUsername string
	DefaultPassword string
}

func Load() (*Config, error) {
	_ = godotenv.Load()

	cfg := &Config{
		Port:            getEnv("PORT", "8080"),
		JWTSecret:       os.Getenv("JWT_SECRET"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		StaticDir:       os.Getenv("STATIC_DIR"),
		CorsOrigins:     splitList(getEnv("CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173,http://localhost:8082,http://127.0.0.1:8082")),
		DefaultUsername: getEnv("DEFAULT_USERNAME", "armin"),
		DefaultPassword: getEnv("DEFAULT_PASSWORD", "Lexmora@2024"),
	}

	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func splitList(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}
