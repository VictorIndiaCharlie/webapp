import math
import random
import itertools
from collections import Counter, defaultdict
from typing import Dict, List, Optional


class MarkovInventor:
    def __init__(self, words: List[str], seed: int = 42):
        self.rng = random.Random(seed)
        self.transitions: Dict[str, Counter] = defaultdict(Counter)
        self._train(words)

    def _train(self, words: List[str]) -> None:
        for w in words:
            w = w.lower()
            if not w.isalpha():
                continue
            padded = "^" + w + "$"
            for i in range(len(padded) - 1):
                self.transitions[padded[i]][padded[i + 1]] += 1

    def _sample_next(self, prev: str) -> Optional[str]:
        if prev not in self.transitions:
            return None
        choices = self.transitions[prev]
        total = sum(choices.values())
        r = self.rng.random() * total
        acc = 0.0
        for ch, cnt in choices.items():
            acc += cnt
            if r <= acc:
                return ch
        return next(iter(choices))

    def generate(self, length: int, tries: int = 30) -> Optional[str]:
        for _ in range(tries):
            chars: List[str] = []
            prev = "^"
            for _ in range(length):
                nxt = self._sample_next(prev)
                if nxt is None or nxt == "$":
                    break
                chars.append(nxt)
                prev = nxt
            if len(chars) == length:
                return "".join(chars)
        return None

    def generate_corpus(
        self, count_per_length: Dict[int, int], exclude: set
    ) -> List[str]:
        out: set = set()
        for length, target in count_per_length.items():
            attempts = 0
            made = 0
            while made < target and attempts < target * 40:
                w = self.generate(length)
                if w and w not in exclude and w not in out:
                    out.add(w)
                    made += 1
                attempts += 1
        return list(out)

    def score_word(self, word: str) -> float:
        """Uses the Markov transitions to score how 'pronounceable' a word is."""
        score = 0.0
        prev = "^"
        for ch in word:
            if prev in self.transitions and ch in self.transitions[prev]:
                total = sum(self.transitions[prev].values())
                score += math.log(self.transitions[prev][ch] / total)
            else:
                return -9999.0  # Impossible transition
            prev = ch

        # Check if it can end properly
        if prev in self.transitions and "$" in self.transitions[prev]:
            total = sum(self.transitions[prev].values())
            score += math.log(self.transitions[prev]["$"] / total)
        else:
            return -9999.0

        return score

    def generate_exact_anagrams(self, pool: str, count: int = 10) -> List[str]:
        """Generates exact anagrams of the input pool, sorted by pronounceability."""
        if len(pool) > 8:
            return []  # Prevent explosion for very long names

        perms = set("".join(p) for p in itertools.permutations(pool))

        # Filter out impossible combinations first to save sorting time
        scored = [(self.score_word(p), p) for p in perms if p != pool]

        # Sort by highest score first
        scored.sort(reverse=True)

        results = []
        for score, word in scored:
            if score > -9999.0:  # Must be pronounceable
                results.append(word)
                if len(results) >= count:
                    break
        return results
