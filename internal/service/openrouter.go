package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const defaultOpenRouterBaseURL = "https://openrouter.ai/api/v1"

type OpenRouterClient struct {
	baseURL string
	client  *http.Client
}

func NewOpenRouterClient(baseURL, httpProxy string) (*OpenRouterClient, error) {
	if baseURL == "" {
		baseURL = defaultOpenRouterBaseURL
	}
	baseURL = strings.TrimRight(baseURL, "/")
	// Legacy callers may pass the full chat completions URL.
	baseURL = strings.TrimSuffix(baseURL, "/chat/completions")

	transport := http.DefaultTransport.(*http.Transport).Clone()
	if strings.TrimSpace(httpProxy) != "" {
		proxyURL, err := url.Parse(httpProxy)
		if err != nil {
			return nil, fmt.Errorf("openrouter http proxy: %w", err)
		}
		transport.Proxy = http.ProxyURL(proxyURL)
	}

	return &OpenRouterClient{
		baseURL: baseURL,
		client: &http.Client{
			Timeout:   120 * time.Second,
			Transport: transport,
		},
	}, nil
}

type chatRequest struct {
	Model    string        `json:"model"`
	Messages []chatMessage `json:"messages"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

func (c *OpenRouterClient) Complete(ctx context.Context, apiKey, model, systemPrompt, userText string) (string, error) {
	if strings.TrimSpace(apiKey) == "" {
		return "", errors.New("openrouter API key is not configured")
	}
	if strings.TrimSpace(model) == "" {
		return "", errors.New("model is not configured")
	}

	reqBody := chatRequest{
		Model: model,
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userText},
		},
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	respBody, status, err := c.do(ctx, http.MethodPost, "/chat/completions", apiKey, body)
	if err != nil {
		return "", err
	}
	if status >= 400 {
		return "", fmt.Errorf("openrouter status %d: %s", status, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return "", fmt.Errorf("unmarshal response: %w", err)
	}
	if chatResp.Error != nil {
		return "", fmt.Errorf("openrouter error: %s", chatResp.Error.Message)
	}
	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("openrouter returned no choices")
	}

	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	return strings.TrimSpace(content), nil
}

type OpenRouterModel struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	ContextLength int    `json:"context_length"`
}

type modelsListResponse struct {
	Data []struct {
		ID            string `json:"id"`
		Name          string `json:"name"`
		ContextLength int    `json:"context_length"`
	} `json:"data"`
}

func (c *OpenRouterClient) ListModels(ctx context.Context, apiKey, q string, limit int) ([]OpenRouterModel, error) {
	if strings.TrimSpace(apiKey) == "" {
		return nil, errors.New("openrouter API key is not configured")
	}
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}

	params := url.Values{}
	params.Set("limit", fmt.Sprintf("%d", limit))
	if strings.TrimSpace(q) != "" {
		params.Set("q", strings.TrimSpace(q))
	}

	respBody, status, err := c.do(ctx, http.MethodGet, "/models?"+params.Encode(), apiKey, nil)
	if err != nil {
		return nil, err
	}
	if status >= 400 {
		return nil, fmt.Errorf("openrouter status %d: %s", status, string(respBody))
	}

	var parsed modelsListResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("unmarshal models: %w", err)
	}

	out := make([]OpenRouterModel, 0, len(parsed.Data))
	for _, m := range parsed.Data {
		name := m.Name
		if name == "" {
			name = m.ID
		}
		out = append(out, OpenRouterModel{
			ID:            m.ID,
			Name:          name,
			ContextLength: m.ContextLength,
		})
	}
	return out, nil
}

type CreditsInfo struct {
	Source         string   `json:"source"`
	Remaining      *float64 `json:"remaining"`
	TotalCredits   *float64 `json:"total_credits"`
	TotalUsage     *float64 `json:"total_usage"`
	LimitRemaining *float64 `json:"limit_remaining"`
	Usage          *float64 `json:"usage"`
}

type creditsResponse struct {
	Data struct {
		TotalCredits float64 `json:"total_credits"`
		TotalUsage   float64 `json:"total_usage"`
	} `json:"data"`
}

type keyResponse struct {
	Data struct {
		Limit          *float64 `json:"limit"`
		LimitRemaining *float64 `json:"limit_remaining"`
		Usage          float64  `json:"usage"`
	} `json:"data"`
}

func (c *OpenRouterClient) GetCredits(ctx context.Context, apiKey string) (*CreditsInfo, error) {
	if strings.TrimSpace(apiKey) == "" {
		return nil, errors.New("openrouter API key is not configured")
	}

	respBody, status, err := c.do(ctx, http.MethodGet, "/credits", apiKey, nil)
	if err == nil && status < 400 {
		var parsed creditsResponse
		if err := json.Unmarshal(respBody, &parsed); err != nil {
			return nil, fmt.Errorf("unmarshal credits: %w", err)
		}
		total := parsed.Data.TotalCredits
		usage := parsed.Data.TotalUsage
		remaining := total - usage
		return &CreditsInfo{
			Source:       "credits",
			Remaining:    &remaining,
			TotalCredits: &total,
			TotalUsage:   &usage,
		}, nil
	}

	respBody, status, err = c.do(ctx, http.MethodGet, "/key", apiKey, nil)
	if err != nil {
		return nil, err
	}
	if status >= 400 {
		return nil, fmt.Errorf("openrouter status %d: %s", status, string(respBody))
	}

	var parsed keyResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("unmarshal key: %w", err)
	}
	usage := parsed.Data.Usage
	info := &CreditsInfo{
		Source:         "key",
		Usage:          &usage,
		LimitRemaining: parsed.Data.LimitRemaining,
	}
	if parsed.Data.LimitRemaining != nil {
		info.Remaining = parsed.Data.LimitRemaining
	}
	return info, nil
}

func (c *OpenRouterClient) do(ctx context.Context, method, path, apiKey string, body []byte) ([]byte, int, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return nil, 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("openrouter request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, fmt.Errorf("read response: %w", err)
	}
	return respBody, resp.StatusCode, nil
}
