"""Generate synthetic NU-style diplomas and transcripts with salted commitments.

Output: data/synthetic_credentials.json
    {"seed": ..., "credentials": [{"id", "type", "document", "documentJson",
                                    "salt", "documentHash", "commitment"}, ...]}

All people and records are fictional. Salts are drawn from a *seeded* RNG so
the dataset is reproducible; a real deployment must use a CSPRNG
(e.g. Python's `secrets.token_bytes(32)`).

Usage:  python experiments/credentials.py [--count 50]
"""

from __future__ import annotations

import argparse
import json
import random

from common import DATA, SEED, canonical_json, commitment, document_hash, hex32

FIRST = ["Aigerim", "Nurlan", "Dana", "Arman", "Madina", "Yerlan", "Aruzhan", "Timur", "Zhanna", "Daniyar"]
LAST = ["Synthetic", "Example", "Testova", "Sampleuly", "Placeholder"]
PROGRAMS = [
    ("BSc Computer Science", "SEDS"),
    ("BSc Mathematics", "SSH"),
    ("BEng Electrical and Computer Engineering", "SEDS"),
    ("BA Economics", "SSH"),
    ("BSc Biological Sciences", "SSH"),
]
COURSES = ["CSCI 151", "CSCI 152", "CSCI 235", "CSCI 270", "CSCI 361", "CSCI 435", "MATH 161", "MATH 273"]
GRADES = ["A", "A-", "B+", "B", "B-", "C+", "C"]
HONOURS = ["None", "Cum Laude", "Magna Cum Laude", "Summa Cum Laude"]


def make_credential(i: int, rng: random.Random) -> dict:
    degree, school = rng.choice(PROGRAMS)
    student = {
        "studentId": f"S-{i:06d}",
        "studentName": f"{rng.choice(FIRST)} {rng.choice(LAST)}",
    }
    if i % 2 == 0:
        doc = {
            "credentialType": "BachelorDiploma",
            "degree": degree,
            "school": school,
            "graduationDate": f"2026-06-{rng.randint(10, 20):02d}",
            "honours": rng.choice(HONOURS),
            "issuer": "NU-SYNTHETIC",
            **student,
        }
    else:
        courses = rng.sample(COURSES, k=5)
        doc = {
            "credentialType": "Transcript",
            "program": degree,
            "issuer": "NU-SYNTHETIC",
            "issueDate": "2026-07-01",
            "courses": [{"code": c, "credits": 6, "grade": rng.choice(GRADES)} for c in courses],
            "cumulativeGpa": round(rng.uniform(2.5, 4.0), 2),
            **student,
        }
    return doc


def generate(count: int, seed: int = SEED) -> dict:
    rng = random.Random(seed)
    creds = []
    for i in range(1, count + 1):
        doc = make_credential(i, rng)
        salt = rng.randbytes(32)  # reproducible; use secrets.token_bytes(32) in practice
        dh = document_hash(doc)
        creds.append(
            {
                "id": doc["studentId"] + ("-DIP" if doc["credentialType"] == "BachelorDiploma" else "-TR"),
                "type": doc["credentialType"],
                "document": doc,
                "documentJson": canonical_json(doc).decode("utf-8"),
                "salt": hex32(salt),
                "documentHash": hex32(dh),
                "commitment": hex32(commitment(dh, salt)),
            }
        )
    return {"seed": seed, "note": "Synthetic data. Not real persons or records.", "credentials": creds}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--count", type=int, default=50)
    args = ap.parse_args()
    DATA.mkdir(exist_ok=True)
    out = DATA / "synthetic_credentials.json"
    out.write_text(json.dumps(generate(args.count), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {args.count} credentials -> {out.relative_to(DATA.parent)}")


if __name__ == "__main__":
    main()
