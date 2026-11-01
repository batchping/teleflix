-- ==============================================================================
-- TeleFlix Cloudflare D1 Unified Database Schema
-- Complete, self-contained schema for video hosting, HLS streaming & Telegram cleanup
-- Optimized for Zero-Cost: Single-row segments_blob minimizes D1 writes by 99.8%
-- ==============================================================================

-- 1. Videos Catalog & Metadata Table (with embedded segments_blob)
CREATE TABLE IF NOT EXISTS videos (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    size_bytes INTEGER NOT NULL DEFAULT 0,
    duration REAL DEFAULT 0,
    total_segments INTEGER NOT NULL DEFAULT 0,
    target_segment_duration REAL DEFAULT 4.0,
    poster_file_id TEXT,
    poster_message_id INTEGER,
    status TEXT DEFAULT 'queued', -- 'queued' | 'processing' | 'ready' | 'failed' | 'deleting' | 'delete_failed'
    progress INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    segments_blob TEXT,               -- Single JSON array containing all segment metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- Performance & Query Optimization Indexes
-- ==============================================================================

-- Fast pagination & catalog ordering for the dashboard (GET /api/videos)
CREATE INDEX IF NOT EXISTS idx_videos_created 
ON videos(created_at DESC);
