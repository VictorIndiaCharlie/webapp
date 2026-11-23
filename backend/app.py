import os
import re
import time
import sys
import random
import threading
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

# Reduced Markov corpus to save RAM since we now have 2M real words
CORPUS_PER_LENGTH = {2: 500, 3: 1000, 4: 2000, 5: 2000, 6: 1000}

# ---------------------------------------------------------------- helpers
def strip_diacritics(s: str) -> str:
    table = {
        "ă":"a","â":"a","î":"i","ș":"s","ş":"s","ț":"t","ţ":"t",
        "á":"a","à":"a","ä":"a","é":"e","è":"e","ë":"e","í":"i","ì":"i",
        "ï":"i","ó":"o","ò":"o","ö":"o","ú":"u","ù":"u","ü":"u","ç":"c","ñ":"n",
    }
    return "".join(table.get(c, c) for c in s.lower())

def letter_pool(raw: str) -> str:
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
IS_LOADED = False
INVENTOR: MarkovInventor = None

@lru_cache(maxsize=1000)
def _find_all(input_key: str, input_len: int, max_words: int, invented: bool) -> dict:
    input_counts = to_counts(input_key)
    t0 = time.perf_counter()

    # 1. Exact single words
    exact = list(EXACT_MAP.get(input_key, []))
    if invented:
        exact += list(INVENTED_MAP.get(input_key, []))

    # 2. Sub-anagrams (Capped at 100 to save UI processing)
    sub_anagrams = []
    subset_keys = []
    for key in ALL_KEYS_SORTED:
        if len(key) < input_len and is_subset_key(key, input_counts):
            subset_keys.append(key)
            sub_anagrams.extend(EXACT_MAP.get(key, []))
            if invented:
                sub_anagrams.extend(INVENTED_MAP.get(key, []))
                
    sub_anagrams = sorted(list(set(sub_anagrams)), key=lambda w: (-len(w), w))[:100]
    sub_anagrams.sort(key=lambda w: (len(w), w))

    # 3. Multi-Word Exact Phrases (Recursive Backtracking)
    phrases = []
    
    def backtrack(start_idx, remaining_counts, current_words):
        if sum(remaining_counts) == 0 and len(current_words) > 1:
            phrases.append(list(current_words))
            return
        if len(current_words) >= max_words:
            return
            
        for i in range(start_idx, len(subset_keys)):
            key = subset_keys[i]
            if is_subset_key(key, remaining_counts):
                new_counts = subtract_counts(remaining_counts, to_counts(key))
                words = EXACT_MAP.get(key, [])
                if invented:
                    words += INVENTED_MAP.get(key, [])
                    
                for word in words:
                    current_words.append(word)
                    backtrack(i, new_counts, current_words)
                    current_words.pop()

    backtrack(0, input_counts, [])
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
    try: yield conn
    finally: conn.close()

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
        conn.commit()

def build_dictionaries():
    global EXACT_MAP, INVENTED_MAP, ALL_KEYS_SORTED, INVENTED_SET, IS_LOADED, INVENTOR
    print("[init] Loading 2M word dictionary into memory...")
    t0 = time.perf_counter()
    
    try:
        with open(WORDLIST_PATH, "r", encoding="utf-8") as f:
            real_words = list(set(sys.intern(line.strip().lower()) for line in f if line.strip().isalpha()))
    except FileNotFoundError:
        print(f"[init] WARNING: {WORDLIST_PATH} not found.")
        return

    # Randomly sample 50k words for the Markov chain so we get a true mix of the language
    random.seed(42)
    training_sample = random.sample(real_words, min(50000, len(real_words)))
    
    print("[init] Training Markov inventor...")
    INVENTOR = MarkovInventor(training_sample)
    invented = INVENTOR.generate_corpus(CORPUS_PER_LENGTH, exclude=set(real_words))
    print(f"[init] Generated {len(invented)} invented words.")

    for w in real_words:
        EXACT_MAP[normalize_and_sort(w)].append(w)
    for w in invented:
        INVENTED_MAP[normalize_and_sort(w)].append(w)
    INVENTED_SET = set(invented)

    all_keys = set(EXACT_MAP.keys()) | set(INVENTED_MAP.keys())
    ALL_KEYS_SORTED = sorted(all_keys, key=lambda k: (len(k), k))
    
    elapsed = time.perf_counter() - t0
    print(f"[init] Loaded {len(real_words)} real words in {elapsed:.1f}s")
    IS_LOADED = True

# ---------------------------------------------------------------- app
app = FastAPI(title="Anagram Generator API", version="3.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(status_code=500, content={"detail": f"Internal Server Error: {str(exc)}"})

@app.on_event("startup")
def on_startup():
    for _ in range(10):
        try:
            ensure_schema()
            break
        except Exception:
            time.sleep(2)
            
    thread = threading.Thread(target=build_dictionaries)
    thread.daemon = True
    thread.start()

class WordIn(BaseModel):
    word: str
    @field_validator("word")
    @classmethod
    def _validate(cls, v: str) -> str:
        cleaned = letter_pool(v.strip())
        if not cleaned: raise ValueError("word must contain letters")
        return cleaned

@app.get("/health")
def health():
    if not IS_LOADED:
        raise HTTPException(status_code=503, detail="Dictionary is still loading into memory...")
    try:
        with db_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return {"status": "ok"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"db unreachable: {exc}") from exc

@app.get("/api/anagrams")
def get_anagrams(word: str = Query(..., min_length=1, max_length=60), max_words: int = Query(3, ge=1, le=5)):
    if not IS_LOADED:
         raise HTTPException(status_code=503, detail="Dictionary is still loading. Please wait.")
    
    raw = word.strip()
    pool = letter_pool(raw)
    if not pool: raise HTTPException(status_code=400, detail="word must contain letters")

    input_key = "".join(sorted(pool))
    
    # 1. Get the standard dictionary results
    result = _find_all(input_key, len(input_key), max_words, invented=True)
    
    exact_list = [{"word": w, "invented": w in INVENTED_SET} for w in result["exact"] if w != pool]
    
    # 2. Generate on-the-fly exact invented anagrams for the specific input
    if INVENTOR and len(pool) <= 8:
        existing_words = {w["word"] for w in exact_list}
        on_the_fly = INVENTOR.generate_exact_anagrams(pool, count=10)
        
        for w in on_the_fly:
            if w not in existing_words and w != pool:
                exact_list.append({"word": w, "invented": True})

    return {
        "input": raw,
        "exact": exact_list,
        "sub_anagrams": [{"word": w, "invented": w in INVENTED_SET} for w in result["sub_anagrams"]],
        "phrases": result["phrases"],
        "stats": {
            "exact_count": len(exact_list),
            "sub_count": len(result["sub_anagrams"]),
            "phrase_count": len(result["phrases"]),
            "total": len(exact_list) + len(result["sub_anagrams"]) + len(result["phrases"]),
            "time_ms": result["time_ms"]
        },
    }

@app.get("/api/words/random")
def random_word():
    with db_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT word FROM words ORDER BY RANDOM() LIMIT 1")
        row = cur.fetchone()
    if row is None: raise HTTPException(status_code=404, detail="dictionary empty")
    return {"word": row[0]}

@app.post("/api/words", status_code=201)
def add_word(payload: WordIn):
    word = payload.word
    key = normalize_and_sort(word)
    with db_conn() as conn, conn.cursor() as cur:
        cur.execute("INSERT INTO words (word, sorted_letters) VALUES (%s, %s) ON CONFLICT DO NOTHING RETURNING word;", (word, key))
        inserted = cur.fetchone() is not None
        conn.commit()
    return {"word": word, "message": None if inserted else "already exists"}