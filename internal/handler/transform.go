package handler

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ArminDashti/lexmora-api/internal/domain"
	"github.com/ArminDashti/lexmora-api/internal/repository"
	"github.com/ArminDashti/lexmora-api/internal/service"
)

func (h *Handler) Transform(c *gin.Context) {
	var req service.TransformRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	result, err := h.transformService.Transform(c.Request.Context(), req)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}

func (h *Handler) GetTransformOptions(c *gin.Context) {
	opts, err := h.transformService.GetOptions(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, opts)
}

func queryInt(c *gin.Context, key string, defaultVal int) int {
	v := c.Query(key)
	if v == "" {
		return defaultVal
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return defaultVal
	}
	return n
}

func parseDayBound(value string, endOfDay bool) (*time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	day, err := time.ParseInLocation("2006-01-02", value, time.Local)
	if err != nil {
		return nil, err
	}
	if endOfDay {
		// Exclusive upper bound: start of next day.
		next := day.AddDate(0, 0, 1)
		return &next, nil
	}
	return &day, nil
}

func (h *Handler) ListHistory(c *gin.Context) {
	from, err := parseDayBound(c.Query("from"), false)
	if err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: "invalid from date (use YYYY-MM-DD)", Code: "VALIDATION_ERROR"})
		return
	}
	to, err := parseDayBound(c.Query("to"), true)
	if err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: "invalid to date (use YYYY-MM-DD)", Code: "VALIDATION_ERROR"})
		return
	}

	filter := repository.HistoryListFilter{
		SortBy:    c.DefaultQuery("sort_by", "datetime"),
		SortOrder: c.DefaultQuery("sort_order", "desc"),
		Limit:     queryInt(c, "limit", 50),
		Offset:    queryInt(c, "offset", 0),
		Type:      c.Query("type"),
		From:      from,
		To:        to,
	}

	page, err := h.historyService.List(c.Request.Context(), filter)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, page)
}

func (h *Handler) GetHistory(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	item, err := h.historyService.Get(c.Request.Context(), id.String())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *Handler) DeleteHistory(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	if err := h.historyService.Delete(c.Request.Context(), id.String()); err != nil {
		h.handleError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *Handler) GetStats(c *gin.Context) {
	stats, err := h.statsService.Get(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, stats)
}
