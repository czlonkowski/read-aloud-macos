"""Sentence chunking utility.

Mirrors the Swift `SentenceChunker` so the client and server agree on segment
boundaries. The Swift app pre-chunks per-request, so this is mostly a defensive
re-split for safety + a place to do language-specific sentence detection later.
"""

from __future__ import annotations

import re

# A naive sentence splitter that works well enough for Polish and English. We
# avoid pulling in nltk/spacy here because the sidecar is meant to start fast.
_SENT_RE = re.compile(r"(?<=[\.\?\!…])\s+(?=[A-ZĄĆĘŁŃÓŚŹŻ\"\'“])")


def split_sentences(text: str, min_chars: int = 80, max_chars: int = 600) -> list[str]:
    text = text.strip()
    if not text:
        return []
    raw = _SENT_RE.split(text)
    sentences = [s.strip() for s in raw if s.strip()]
    if not sentences:
        return [text]

    out: list[str] = []
    buf = ""
    for s in sentences:
        if not buf:
            buf = s
        elif len(buf) < min_chars and len(buf) + 1 + len(s) <= max_chars:
            buf = f"{buf} {s}"
        else:
            out.append(buf)
            buf = s
    if buf:
        out.append(buf)
    return out
