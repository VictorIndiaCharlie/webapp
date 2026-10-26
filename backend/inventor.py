"""
Markov-chain pseudo-word generator.
Trains a bigram model on the real dictionary at startup, then generates
pronounceable synthetic words. These are added to the in-memory search map
so they cost nothing at query time.
"""
import random
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
