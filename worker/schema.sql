-- ==============================================================================
-- TeleFlix Cloudflare D1 Unified Database Schema
-- Complete, self-contained schema for video hosting, HLS streaming & Telegram cleanup
-- Optimized for Zero-Cost: Single-row segments_blob minimizes D1 writes by 99.8%
--
-- Fresh installs: run this file.
-- Existing installs: run migrations/002_*.sql instead (this file's
-- `idx_videos_source_url` index needs the column added by that migration).
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
    -- custom_poster_url: user-uploaded or external HTTPS image URL for poster.
    -- Overrides auto-extracted poster_file_id when present; falls back to it when NULL.
    custom_poster_url TEXT,
    -- bot_token: the Telegram bot used to upload all segments for this video.
    -- Used at stream time to call the correct bot's getFile endpoint.
    -- NULL for videos ingested before multi-bot support was added (falls back to first token in TG_BOT_TOKENS).
    bot_token TEXT,
    -- source_url: normalized original HTTP(S) URL this video was ingested from.
    -- Used for duplicate detection and for re-dispatching failed/stale jobs.
    -- Never returned to unauthenticated callers (may contain signed-URL tokens).
    source_url TEXT,
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

-- 4. Series / Playlists -- ordered collections of videos for binge-watching
CREATE TABLE IF NOT EXISTS playlists (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS playlist_items (
    playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    video_id TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (playlist_id, video_id)
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

-- Folder-filtered catalog pages sorted by newest (covers WHERE + ORDER BY)
CREATE INDEX IF NOT EXISTS idx_videos_folder_created
ON videos(folder_id, created_at DESC);

-- Fast status filtering & runner stale-job sweeps
CREATE INDEX IF NOT EXISTS idx_videos_status_updated
ON videos(status, updated_at);

-- Status-filtered catalog pages sorted by newest (covers WHERE + ORDER BY)
CREATE INDEX IF NOT EXISTS idx_videos_status_created
ON videos(status, created_at DESC);

-- Storage panel: largest ready videos without a full sort
CREATE INDEX IF NOT EXISTS idx_videos_status_size
ON videos(status, size_bytes DESC);

-- Catalog sort modes that bypass created_at
CREATE INDEX IF NOT EXISTS idx_videos_title_lower
ON videos(lower(title));

CREATE INDEX IF NOT EXISTS idx_videos_size_bytes
ON videos(size_bytes DESC);

CREATE INDEX IF NOT EXISTS idx_videos_duration
ON videos(duration DESC);

-- Fast duplicate detection by original source URL
CREATE INDEX IF NOT EXISTS idx_videos_source_url
ON videos(source_url);

-- Fast playlist lookups and ordered playback
CREATE INDEX IF NOT EXISTS idx_playlist_items_playlist
ON playlist_items(playlist_id, position);

CREATE INDEX IF NOT EXISTS idx_playlist_items_video
ON playlist_items(video_id);
