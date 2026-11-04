-- ==============================================================================
-- TeleFlix Cloudflare D1 Unified Database Schema
-- Complete, self-contained schema for video hosting, HLS streaming & Telegram cleanup
-- Optimized for Zero-Cost: Single-row segments_blob minimizes D1 writes by 99.8%
-- ==============================================================================

-- 1. Folders -- lightweight grouping for the dashboard
CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Videos Catalog & Metadata Table (with embedded segments_blob & folder_id)
CREATE TABLE IF NOT EXISTS videos (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    size_bytes INTEGER NOT NULL DEFAULT 0,
    duration REAL DEFAULT 0,
    total_segments INTEGER NOT NULL DEFAULT 0,
    target_segment_duration REAL DEFAULT 4.0,
    poster_file_id TEXT,
    poster_message_id INTEGER,
    -- bot_token: the Telegram bot used to upload all segments for this video.
    -- Used at stream time to call the correct bot's getFile endpoint.
    -- NULL for videos ingested before multi-bot support was added (falls back to first token in TG_BOT_TOKENS).
    bot_token TEXT,
    folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'queued',
    progress INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    segments_blob TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Settings -- general-purpose key/value store for persistent worker state
--    Used for: bot_round_robin_index (atomically incremented counter for equal bot distribution)
CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);

-- ==============================================================================
-- Performance & Query Optimization Indexes
-- ==============================================================================

-- Fast pagination & catalog ordering for the dashboard (GET /api/videos)
CREATE INDEX IF NOT EXISTS idx_videos_created 
ON videos(created_at DESC);

-- Fast folder filtering for dashboard views
CREATE INDEX IF NOT EXISTS idx_videos_folder
ON videos(folder_id);
