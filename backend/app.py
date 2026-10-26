import os
import re
import time
from collections import defaultdict
from contextlib import contextmanager
from functools import lru_cache
from typing import Dict, List, Tuple

import psycopg2
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator

from inventor import MarkovInventor

# ---------------------------------------------------------------- config
DB_CONFIG = {
    "host": os.getenv("POSTGRES_HOST", "db"),
    "port": int(os.getenv("POSTGRES_PORT", "5432")),
    "dbname": os.getenv("POSTGRES_DB", "anagrams"),
    "user": os.getenv("POSTGRES_USER", "anagram"),
    "password": os.getenv("POSTGRES_PASSWORD", "anagram"),
}
WORDLIST_PATH = os.getenv("WORDLIST_PATH", "/app/wordlist.txt")

CORPUS_PER_LENGTH = {2: 400, 3: 1500, 4: 3000, 5: 3500, 6: 2500}

SEED_NAMES = [
    "andrei","andreea","alexandru","maria","elena","ioana","mihai","gabriel",
    "ana","cristian","daniel","luca","stefan","ionut","alina","alexandra",
    "bogdan","catalin","dragos","florin","george","ion","laurentiu","marius",
    "nicolae","oana","paul","radu","sorin","tudor","vasile","dumitru",
    "gheorghe","constantin","adrian","cornel","vlad",
    "matteo","sophie","luis","pierre","giulia","hans","klaus","nikola","olga",
    "sven","ivan","lars","emma","olivia","liam","noah","lucas","sofia","alice",
    "hugo","arthur","leo","adam","david","karl","franz","giovanni","isabella",
    "charlotte","amelia","mia","leon","felix","maximilian","anna","lena","nina",
    "clara","laura","julia","sara","elisa","martina","francesca","chiara",
]

# ---------------------------------------------------------------- helpers
def strip_diacritics(s: str) -> str:
    """Basic mapping for Romanian/European accents so 'Ștefan' → 'stefan'."""
    table = {
        "ă":"a","â":"a","î":"i","ș":"s","ş":"s","ț":"t","ţ":"t",
        "á":"a","à":"a","ä":"a","é":"e","è":"e","ë":"e","í":"i","ì":"i",
        "ï":"i","ó":"o","ò":"o","ö":"o","ú":"u","ù":"u","ü":"u","ç":"c","ñ":"n",
    }
    return "".join(table.get(c, c) for c in s.lower())


def letter_pool(raw: str) -> str:
    """Return just a-z letters — spaces and punctuation stripped, accents normalized."""
    s = strip_diacritics(raw)
    return re.sub(r"[^a-z]", "", s)


def to_counts(word: str) -> Tuple[int, ...]:
    counts = [0] * 26
    for ch in word:
        counts[ord(ch) - 97] += 1
    return tuple(counts)


def counts_key(counts: Tuple[int, ...]) -> str:
    out = []
    for i, n in enumerate(counts):
        if n:
            out.append(chr(97 + i) * n)
    return "".join(out)


def is_subset_key(key: str, input_counts: Tuple[int, ...]) -> bool:
    counts = to_counts(key)
    return all(c <= i for c, i in zip(counts, input_counts))


def subtract_counts(a: Tuple[int, ...], b: Tuple[int, ...]) -> Tuple[int, ...]:
    return tuple(x - y for x, y in zip(a, b))


def normalize_and_sort(word: str) -> str:
    return "".join(sorted(letter_pool(word)))


# ---------------------------------------------------------------- state
EXACT_MAP: Dict[str, List[str]] = defaultdict(list)
INVENTED_MAP: Dict[str, List[str]] = defaultdict(list)
ALL_KEYS_SORTED: List[str] = []
INVENTED_SET: set = set()


@lru_cache(maxsize=4000)
def _find_all(input_key: str, input_len: int, max_words: int, invented: bool) -> dict:
    input_counts = to_counts(input_key)
    t0 = time.perf_counter()

    # 1) Exact anagrams
    exact = list(EXACT_MAP.get(input_key, []))
    if invented:
        exact += list(INVENTED_MAP.get(input_key, []))

    # 2) Sub-anagrams
    sub_anagrams: List[str] = []
    subset_keys: List[str] = []
    for key in ALL_KEYS_SORTED:
        if len(key) >= input_len:
            continue
        if is_subset_key(key, input_counts):
            subset_keys.append(key)
            sub_anagrams.extend(EXACT_MAP.get(key, []))
            if invented:
                sub_anagrams.extend(INVENTED_MAP.get(key, []))
    sub_anagrams.sort(key=lambda w: (len(w), w))

    # 3) Phrases (real words only — invented would explode the search)
    phrases: List[List[str]] = []
    seen = set()

    def add_phrase(words: List[str]):
        canon = tuple(sorted(words))
        if canon in seen:
            return
        seen.add(canon)
        phrases.append(words)

    if max_words >= 2:
        for key1 in subset_keys:
            if key1 not in EXACT_MAP:
                continue
            remaining = subtract_counts(input_counts, to_counts(key1))
            rem_key = counts_key(remaining)
            if not rem_key or rem_key not in EXACT_MAP or key1 > rem_key:
                continue
            for w1 in EXACT_MAP[key1]:
                for w2 in EXACT_MAP[rem_key]:
                    if key1 == rem_key and w1 > w2:
                        continue
                    add_phrase([w1, w2])

    if max_words >= 3:
        for i, key1 in enumerate(subset_keys):
            if key1 not in EXACT_MAP:
                continue
            c1 = to_counts(key1)
            remaining1 = subtract_counts(input_counts, c1)
            if sum(remaining1) < 2:
                continue
            for key2 in subset_keys[i:]:
                if key1 >= key2 or key2 not in EXACT_MAP:
                    continue
                if not is_subset_key(key2, remaining1):
                    continue
                remaining2 = subtract_counts(remaining1, to_counts(key2))
                rem2_key = counts_key(remaining2)
                if not rem2_key or rem2_key not in EXACT_MAP or key2 > rem2_key:
                    continue
                for w1 in EXACT_MAP[key1]:
                    for w2 in EXACT_MAP[key2]:
                        for w3 in EXACT_MAP[rem2_key]:
                            add_phrase([w1, w2, w3])

    phrases.sort(key=lambda p: (len(p), " ".join(p)))
    elapsed = (time.perf_counter() - t0) * 1000

    return {
        "exact": exact,
        "sub_anagrams": sub_anagrams,
        "phrases": phrases[:300],
        "time_ms": round(elapsed, 2),
    }


# ---------------------------------------------------------------- DB + startup
@contextmanager
def db_conn():
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        yield conn
    finally:
        conn.close()


def ensure_schema():
    with db_conn() as conn, conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS words (
                id SERIAL PRIMARY KEY,
                word VARCHAR(100) UNIQUE NOT NULL,
                sorted_letters VARCHAR(100) NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
        """)
        cur.execute("CREATE INDEX IF NOT EXISTS idx_words_sorted_letters ON words (sorted_letters);")
        cur.execute("SELECT COUNT(*) FROM words;")
        if cur.fetchone()[0] == 0:
            for w in SEED_NAMES:
                cur.execute(
                    "INSERT INTO words (word, sorted_letters) VALUES (%s, %s) ON CONFLICT DO NOTHING;",
                    (w, normalize_and_sort(w)),
                )
        conn.commit()


def load_wordlist_from_file() -> List[str]:
    try:
        with open(WORDLIST_PATH, "r", encoding="utf-8") as f:
            return [line.strip().lower() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"[init] WARNING: {WORDLIST_PATH} missing")
        return []


def build_dictionaries():
    global EXACT_MAP, INVENTED_MAP, ALL_KEYS_SORTED, INVENTED_SET
    EXACT_MAP = defaultdict(list)
    INVENTED_MAP = defaultdict(list)

    with db_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT word FROM words;")
        db_words = [r[0] for r in cur.fetchall()]

    file_words = load_wordlist_from_file()
    real_words = set(w.lower() for w in db_words + file_words)
    print(f"[init] Real dictionary: {len(real_words)} words")

    t0 = time.perf_counter()
    inventor = MarkovInventor(real_words)
    invented = inventor.generate_corpus(CORPUS_PER_LENGTH, exclude=real_words)
    print(f"[init] Invented {len(invented)} pseudo-words in {(time.perf_counter()-t0)*1000:.0f} ms")

    for w in real_words:
        EXACT_MAP[normalize_and_sort(w)].append(w)
    for w in invented:
        INVENTED_MAP[normalize_and_sort(w)].append(w)
    INVENTED_SET = set(invented)

    all_keys = set(EXACT_MAP.keys()) | set(INVENTED_MAP.keys())
    ALL_KEYS_SORTED = sorted(all_keys, key=lambda k: (len(k), k))
    print(f"[init] Buckets: {len(ALL_KEYS_SORTED)} "
          f"({len(EXACT_MAP)} real, {len(INVENTED_MAP)} invented)")


# ---------------------------------------------------------------- app
app = FastAPI(title="Anagram Generator API", version="3.0.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_credentials=False,
    allow_methods=["*"], allow_headers=["*"],
)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(status_code=500, content={"detail": f"Internal Server Error: {str(exc)}"})


@app.on_event("startup")
def on_startup():
    last_err = None
    for _ in range(30):
        try:
            ensure_schema()
            build_dictionaries()
            return
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(1)
    print(f"[init] WARNING: failed after 30s: {last_err}")


class WordIn(BaseModel):
    word: str

    @field_validator("word")
    @classmethod
    def _validate(cls, v: str) -> str:
        cleaned = letter_pool(v.strip())
        if not cleaned:
            raise ValueError("word must contain at least one letter")
        return cleaned


@app.get("/health")
def health():
    try:
        with db_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return {"status": "ok"}
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"db unreachable: {exc}") from exc


def tag(w: str) -> dict:
    return {"word": w, "invented": w in INVENTED_SET}


@app.get("/api/anagrams")
def get_anagrams(
    word: str = Query(..., min_length=1, max_length=60),
    max_words: int = Query(2, ge=1, le=3),
    invented: bool = Query(True, description="Include invented pseudo-words"),
):
    raw = word.strip()
    pool = letter_pool(raw)
    if not pool:
        raise HTTPException(status_code=400, detail="word must contain at least one letter")
    if not EXACT_MAP:
        raise HTTPException(status_code=503, detail="dictionary loading, retry in a moment")

    input_key = "".join(sorted(pool))
    result = _find_all(input_key, len(input_key), max_words, invented)

    filtered_exact = [w for w in result["exact"] if w != pool]

    return {
        "input": raw,
        "input_pool": pool,
        "input_key": input_key,
        "input_word_count": len(raw.split()),
        "exact": [tag(w) for w in filtered_exact],
        "sub_anagrams": [tag(w) for w in result["sub_anagrams"][:300]],
        "phrases": result["phrases"],
        "stats": {
            "exact_count": len(filtered_exact),
            "sub_count": len(result["sub_anagrams"]),
            "phrase_count": len(result["phrases"]),
            "total": len(filtered_exact) + len(result["sub_anagrams"]) + len(result["phrases"]),
            "time_ms": result["time_ms"],
            "invented": invented,
        },
    }


@app.get("/api/words/all")
def list_all_words():
    with db_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT word FROM words ORDER BY word ASC;")
        rows = [r[0] for r in cur.fetchall()]
    return {"count": len(rows), "words": rows}


@app.get("/api/words/random")
def random_word():
    with db_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT word FROM words ORDER BY RANDOM() LIMIT 1")
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="dictionary is empty")
    return {"word": row[0]}


@app.post("/api/words", status_code=201)
def add_word(payload: WordIn):
    word = payload.word  # already sanitized by pydantic
    key = normalize_and_sort(word)

    with db_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO words (word, sorted_letters) VALUES (%s, %s) ON CONFLICT DO NOTHING RETURNING word;",
            (word, key),
        )
        inserted = cur.fetchone() is not None
        conn.commit()

    if inserted:
        EXACT_MAP[key].append(word)
        if key not in ALL_KEYS_SORTED:
            ALL_KEYS_SORTED.append(key)
            ALL_KEYS_SORTED.sort(key=lambda k: (len(k), k))
        _find_all.cache_clear()

    return {
        "word": word,
        "message": None if inserted else "already exists in dictionary",
    }
