# 🍿 TeleFlix

> **100% Zero-Cost, Infinitely Scalable Video Streaming Architecture** built entirely on the free tiers of **Cloudflare (Workers, D1, Cache API)**, **GitHub Actions Public Runners (FFmpeg)**, and **Telegram Bot API (as Object Storage)**.

---

## ⚡ Architecture & Optimization Guarantees

TeleFlix eliminates all server, bandwidth, and storage costs through smart orchestration:

```
[Remote Video URL] 
       │ (<= 2GB check)
       ▼
[GitHub Actions Runner] ──(ffmpeg -c copy)──> [HLS ~4s Segments (< 15MB)]
                                                      │
         ┌────────────────────────────────────────────┴────────────────────────────────────────────┐
         │                                                                                         │
         ▼ (Sliding-Window Limiter: 16 msg/min)                                                    ▼ (Batch Ingest)
[Telegram Channels (Sharded Storage)]                                                   [Cloudflare D1 Database]
   (seg_00001 -> file_id)                                                               (Manifests & File IDs)
         │                                                                                         │
         └────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                      │
                                                      ▼
                                       [Cloudflare Worker Proxy]
                                                      │
                                             (Cache API Check)
                                              ├── HIT ──> [0ms Instant Edge Delivery] (Free CDN)
                                              └── MISS ─> Fetch TG -> Save to Edge Cache -> Stream
                                                      │
                                                      ▼
                                              [HLS.js Frontend]
```

### Critical Free-Tier Limits & How We Solve Them

1. **Telegram 20 MB Download Limit (Non-Negotiable)**:
   - Standard Telegram Bot API allows uploads up to 50 MB, but **downloads are strictly capped at 20 MB**.
   - **TeleFlix Solution**: FFmpeg segments video using `-c copy` with `target_duration = 4s`. Even high-bitrate 1080p video generates chunks under $8\text{ MB}$, guaranteeing zero download errors when streaming.

2. **Telegram 20 msgs/min Per-Chat Limit (PDF Benchmarks)**:
   - Sending $\ge 21$ messages in a rolling 60s window results in HTTP 429 flood wait.
   - **TeleFlix Solution**: A mathematically tuned sliding-window rate limiter enforcing:
     - **$\le 16\text{ messages}$** per rolling 60s per channel ($\ge 20\%$ safety margin).
     - **$\ge 1000\text{ ms}$** gap between sends to the same channel.
     - **$20\text{ msg/s}$** global bot ceiling.
     - **Multi-channel sharding**: By supplying $N$ storage channels, throughput scales linearly: $N \times 16\text{ msg/min}$.

3. **Cloudflare Worker Quota & Bandwidth**:
   - Free tier provides 100,000 requests/day.
   - **TeleFlix Solution**: Segments are cached using Cloudflare's **Cache API** (`caches.default`) with `Cache-Control: public, max-age=31536000, immutable`. Once any user plays a video, subsequent plays are served directly from Cloudflare’s worldwide CDN edge ($0$ Telegram API calls, $0\text{ ms}$ compute).

---

## 🛠️ BYOI Setup Guide (Bring Your Own Infrastructure)

### 1. Telegram Storage Setup
1. Create a bot using [@BotFather](https://t.me/BotFather) and copy your **`BOT_TOKEN`**.
2. Create one or more **private Telegram Channels** to act as your storage shards.
3. Add your bot as an **Administrator** in each channel (with permission to post messages).
4. Get your channel IDs (e.g. `-1001234567890`).

---

### 2. Cloudflare Worker & D1 Setup
1. Install Wrangler CLI:
   ```bash
   npm install -g wrangler
   ```
2. Navigate to `worker/`:
   ```bash
   cd worker
   npm install
   ```
3. Create your D1 Database:
   ```bash
   wrangler d1 create teleflix_db
   ```
   *(Copy the generated `database_id` into `worker/wrangler.toml`)*
4. Initialize database schema:
   ```bash
   wrangler d1 execute teleflix_db --remote --file=./schema.sql
   ```
5. Set your Worker secrets:
   ```bash
   wrangler secret put TG_BOT_TOKEN
   wrangler secret put INGEST_SECRET
   ```
6. Deploy the Worker:
   ```bash
   wrangler deploy
   ```
   *(Note your Worker URL: `https://teleflix-worker.<your-subdomain>.workers.dev`)*

---

### 3. GitHub Repository Setup
1. Create a **Public GitHub Repository** (to get unlimited free GitHub Actions runner minutes).
2. Push this codebase to your repository.
3. In your repo, go to **Settings > Secrets and variables > Actions** and add the following repository secrets:
   - `TG_BOT_TOKEN`: Your Telegram Bot token.
   - `TG_CHANNEL_IDS`: Comma-separated list of channel IDs (e.g., `-1001111111111,-1002222222222`).
   - `WORKER_URL`: Your deployed Worker URL (e.g., `https://teleflix-worker.yourname.workers.dev`).
   - `INGEST_SECRET`: The same secret configured on the Worker.
4. Create a **GitHub Personal Access Token (PAT)**:
   - Go to [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens).
   - Generate a token with the `workflow` or `repo` scope so the frontend can dispatch ingestion jobs.

---

### 4. Frontend Launch
You can host the `frontend/` directory on **Cloudflare Pages** (free), **GitHub Pages** (free), or simply open `frontend/index.html` in your browser:

1. Click **⚙️ BYOI Settings** in the top navigation.
2. Enter your:
   - **Cloudflare Worker URL**
   - **Worker Ingest Secret**
   - **GitHub Repo** (`username/repo-name`)
   - **GitHub Personal Access Token**
3. Click **Test Worker** to verify D1 connectivity, then click **Save Configuration**.
4. Click **+ Ingest Video**, paste any direct video URL ($\le 2\text{ GB}$), and hit **Trigger Ingest Runner**.
5. Once GitHub Actions finishes segmenting and uploading, your video appears instantly in the catalog ready for streaming!

---

## 📂 Repository Structure

```
TeleFlix/
├── .github/workflows/
│   └── ingest-video.yml        # GitHub Actions public runner workflow for video processing
├── worker/                     # Cloudflare Edge Worker (Proxy, Edge Caching & D1 Store)
│   ├── src/
│   │   ├── index.ts            # HLS master playlist generator & edge segment proxy
│   │   ├── db.ts               # D1 database client with batch queries
│   │   └── telegram.ts         # Telegram getFile resolver with internal caching
│   ├── schema.sql              # D1 SQL schema for videos and segments
│   ├── wrangler.toml           # Wrangler configuration
│   └── package.json
├── ingest/                     # Ingestion & Upload Engine (runs on GitHub Actions runner)
│   ├── src/
│   │   ├── preflight.ts        # URL alive check, Content-Length <= 2GB, ffprobe probe
│   │   ├── segmenter.ts        # FFmpeg HLS splitting (-c copy, ~4s chunks, <20MB checks)
│   │   ├── rate-limiter.ts     # 16 msg/min sliding-window limiter with 429 backoff
│   │   ├── tg-uploader.ts      # Multi-channel Telegram document uploader
│   │   └── index.ts            # Main CLI orchestrator
│   └── package.json
└── frontend/                   # BYOI Single-Page Web App
    ├── index.html              # HLS player and BYOI configuration modals
    ├── css/style.css           # Modern Netflix dark-theme UI
    └── js/
        ├── app.js              # HLS.js player with live Edge Cache Hit/Miss monitor
        └── config.js           # BYOI credentials manager (LocalStorage)
```

---

## 🔒 Security & Privacy

- All credentials (Bot token, channel IDs, secrets) remain strictly on your own Cloudflare account, GitHub repository, and local browser.
- The Worker does not expose your bot token or internal channel IDs to the public player.
- Storage channels remain completely private.
