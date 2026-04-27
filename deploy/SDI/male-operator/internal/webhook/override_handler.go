/*
Copyright 2024 KETI.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package webhook

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-logr/logr"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/keti-lab/male-operator/internal/override"
)

// OverrideHandler handles HTTP POST requests for override values
type OverrideHandler struct {
	Cache *override.WebhookOverrideCache
}

// NewOverrideHandler creates a new OverrideHandler
func NewOverrideHandler(cache *override.WebhookOverrideCache) *OverrideHandler {
	return &OverrideHandler{Cache: cache}
}

// HandleOverride handles POST /override requests
func (h *OverrideHandler) HandleOverride(w http.ResponseWriter, r *http.Request) {
	logger := log.Log.WithName("override-handler")

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req override.WebhookOverrideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Error(err, "Failed to decode request")
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Validate required fields
	if req.Namespace == "" || req.Name == "" {
		http.Error(w, "namespace and name are required", http.StatusBadRequest)
		return
	}

	// Default TTL to 1 hour if not specified
	ttlSeconds := int64(3600)
	if req.TTLSeconds != nil {
		ttlSeconds = *req.TTLSeconds
	}

	// Store override
	overrideValue := req.ToOverrideValue()
	h.Cache.SetOverride(req.Namespace, req.Name, overrideValue, ttlSeconds)

	logger.Info("Override received",
		"namespace", req.Namespace,
		"name", req.Name,
		"ttl", ttlSeconds)

	// Return success response
	response := map[string]interface{}{
		"status":    "success",
		"namespace": req.Namespace,
		"name":      req.Name,
		"expiresAt": time.Now().Add(time.Duration(ttlSeconds) * time.Second).Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// StartCleanup starts a background goroutine to clean up expired entries
func (h *OverrideHandler) StartCleanup(interval time.Duration, logger logr.Logger) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for range ticker.C {
			h.Cache.CleanupExpired()
		}
	}()
}
