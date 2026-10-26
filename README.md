# Anagram Generator

A tier‑3, three-tier anagram generator:

- **Frontend** — Node.js + Express (serves static UI, proxies `/api` to backend)
- **Backend** — Python + FastAPI (anagram logic + REST API)
- **Database** — PostgreSQL 16 (word dictionary with a pre-sorted letters index)
- **Orchestration** — Docker Compose

## Architecture

```
Browser ──► frontend (Node:3000) ──► backend (FastAPI:8000) ──► postgres (5432)
```

The frontend also serves the static SPA; all `/api/*` calls are proxied to the backend,
so the browser only ever talks to `localhost:3000`.

## Quick Start

```bash
cp .env.example .env      # optional — defaults work out of the box
docker compose up --build
```

Then open <http://localhost:3000>.

The database is auto-seeded from `db/init.sql` on first boot
(with several anagram groups like `listen / silent / enlist / tinsel`).

## Endpoints

| Method | Path                        | Description                                       |
|--------|-----------------------------|---------------------------------------------------|
| GET    | `/api/anagrams?word=<w>`    | Return anagrams for `<w>` (excludes the input).   |
| GET    | `/api/words/random`         | Return a random word from the dictionary.         |
| POST   | `/api/words`                | Add `{ "word": "..." }` to the dictionary.        |
| GET    | `/health`                   | Backend liveness + DB reachability (backend only).|

You can call the backend directly on <http://localhost:8000/docs> (FastAPI Swagger UI).

## How the anagram lookup works

Every word is stored alongside a **bucket key** — its letters, lowercased and sorted.
For example, `listen → eilnst`, and so does `silent`. Finding anagrams is then a
single indexed equality lookup:

```sql
SELECT word FROM words WHERE sorted_letters = $1 AND LOWER(word) <> LOWER($2);
```

`db/init.sql` creates the `words` table, the index on `sorted_letters`, and seeds
sample data in a single `INSERT ... FROM unnest(ARRAY[...])`.

## File structure

```
anagram-generator/
├── docker-compose.yml
├── README.md
├── .env.example
├── .gitignore
├── backend/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── requirements.txt
│   └── app.py
├── db/
│   └── init.sql
└── frontend/
    ├── Dockerfile
    ├── .dockerignore
    ├── package.json
    ├── server.js
    └── public/
        ├── index.html
        ├── style.css
        └── app.js
```

Each Dockerfile uses `context: ./<service>` in `docker-compose.yml`, so build
contexts and file paths align with the directory layout above.

## Local development (without Docker)

**Backend**

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# Point at your local Postgres:
export POSTGRES_HOST=localhost POSTGRES_DB=anagrams POSTGRES_USER=anagram POSTGRES_PASSWORD=anagram
psql -U anagram -d anagrams -f ../db/init.sql
uvicorn app:app --reload --port 8000
```

**Frontend**

```bash
cd frontend
npm install
BACKEND_URL=http://localhost:8000 PORT=3000 npm start
```

## Tear down

```bash
docker compose down            # keep DB volume
docker compose down -v         # wipe DB volume too
```

## Notes / next steps

- Add rate limiting (`slowapi`) or auth in `backend/app.py`.
- Add a `healthcheck` on the frontend if you plan to use it with a reverse proxy.
- The `words` table could be scaled with a GIN/trigram index if you later
  want prefix/pattern search beyond exact anagrams.