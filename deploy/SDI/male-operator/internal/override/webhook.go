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

package override

import (
	"sync"
	"time"
)

// WebhookOverrideCache stores override values received via webhook
type WebhookOverrideCache struct {
	mu    sync.RWMutex
	cache map[string]*CachedOverride
}

// CachedOverride represents a cached override value with TTL
type CachedOverride struct {
	Value     *OverrideValue
	ExpiresAt time.Time
}

// NewWebhookOverrideCache creates a new webhook override cache
func NewWebhookOverrideCache() *WebhookOverrideCache {
	return &WebhookOverrideCache{
		cache: make(map[string]*CachedOverride),
	}
}

// SetOverride stores an override value with TTL
func (c *WebhookOverrideCache) SetOverride(namespace, workloadName string, override *OverrideValue, ttlSeconds int64) {
	c.mu.Lock()
	defer c.mu.Unlock()

	key := cacheKey(namespace, workloadName)
	expiresAt := time.Now().Add(time.Duration(ttlSeconds) * time.Second)

	c.cache[key] = &CachedOverride{
		Value:     override,
		ExpiresAt: expiresAt,
	}
}

// GetOverride retrieves an override value if it exists and hasn't expired
func (c *WebhookOverrideCache) GetOverride(namespace, workloadName string) *OverrideValue {
	c.mu.RLock()
	defer c.mu.RUnlock()

	key := cacheKey(namespace, workloadName)
	cached, ok := c.cache[key]
	if !ok {
		return nil
	}

	// Check if expired
	if time.Now().After(cached.ExpiresAt) {
		// Clean up expired entry
		c.mu.RUnlock()
		c.mu.Lock()
		delete(c.cache, key)
		c.mu.Unlock()
		c.mu.RLock()
		return nil
	}

	return cached.Value
}

// CleanupExpired removes expired entries (should be called periodically)
func (c *WebhookOverrideCache) CleanupExpired() {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	for key, cached := range c.cache {
		if now.After(cached.ExpiresAt) {
			delete(c.cache, key)
		}
	}
}

func cacheKey(namespace, workloadName string) string {
	return namespace + "/" + workloadName
}

// WebhookOverrideRequest represents a webhook override request
type WebhookOverrideRequest struct {
	Namespace  string   `json:"namespace"`
	Name       string   `json:"name"`
	Accuracy   *float64 `json:"accuracy,omitempty"`
	Latency    *float64 `json:"latency,omitempty"`
	Energy     *float64 `json:"energy,omitempty"`
	TTLSeconds *int64   `json:"ttlSeconds,omitempty"`
}

// ToOverrideValue converts a webhook request to OverrideValue
func (r *WebhookOverrideRequest) ToOverrideValue() *OverrideValue {
	return &OverrideValue{
		Accuracy: r.Accuracy,
		Latency:  r.Latency,
		Energy:   r.Energy,
	}
}
