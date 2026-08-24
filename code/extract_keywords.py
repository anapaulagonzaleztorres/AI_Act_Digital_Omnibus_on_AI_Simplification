import pandas as pd
import re

# --- Configuration ---
INPUT_FILE = "eu_feedback_14855.csv"
OUTPUT_CSV = "eu_feedback_filtered.csv"
OUTPUT_XLSX = "eu_feedback_filtered.xlsx"
CONTEXT_CHARS = 1200  # characters before and after a keyword hit to include as context

GROUP1_KEYWORDS = ["digital omnibus", "simplification"]
GROUP2_KEYWORDS = [
    "AI regulatory sandbox",
    "AI standards",
    "harmonised standards",
    "code of practice",
    "GPAI CoP",
]

# --- Load data ---
print("Loading CSV...")
df = pd.read_csv(INPUT_FILE)
print(f"  Loaded {len(df)} rows.")

# --- Helper: find which keywords appear in text (case-insensitive) ---
def find_matches(text, keywords):
    text_lower = text.lower()
    return [kw for kw in keywords if kw.lower() in text_lower]

# --- Helper: extract context window around a keyword match ---
def extract_context(text, keyword, context_chars):
    """Return a snippet of text around each occurrence of keyword."""
    snippets = []
    text_lower = text.lower()
    kw_lower = keyword.lower()
    start = 0
    while True:
        pos = text_lower.find(kw_lower, start)
        if pos == -1:
            break
        snippet_start = max(0, pos - context_chars)
        snippet_end = min(len(text), pos + len(keyword) + context_chars)
        snippets.append(text[snippet_start:snippet_end].strip())
        start = pos + 1
    return snippets

# --- Clean text for Excel (remove illegal control characters) ---
def clean_for_excel(val):
    if isinstance(val, str):
        return re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", val)
    return val

# --- Main extraction loop ---
results = []

for idx, row in df.iterrows():
    text = row.get("attachment_text", "")
    if not isinstance(text, str) or not text.strip():
        continue

    # Step 1: Does this document contain at least one keyword from each group?
    g1_doc = find_matches(text, GROUP1_KEYWORDS)
    g2_doc = find_matches(text, GROUP2_KEYWORDS)
    if not g1_doc or not g2_doc:
        continue  # skip this document entirely

    # Step 2: For each Group 2 keyword found, extract context around it
    #         and check that the context also contains a Group 1 keyword
    seen_snippets = set()
    for kw2 in g2_doc:
        for snippet in extract_context(text, kw2, CONTEXT_CHARS):
            g1_in_snippet = find_matches(snippet, GROUP1_KEYWORDS)
            if g1_in_snippet:
                # Deduplicate very similar snippets from the same document
                key = (idx, snippet[:80])
                if key in seen_snippets:
                    continue
                seen_snippets.add(key)
                results.append({
                    "entry_id": idx,
                    "date": row.get("date", ""),
                    "type": row.get("type", ""),
                    "name": row.get("name", ""),
                    "country": row.get("country", ""),
                    "url": row.get("url", ""),
                    "matched_paragraph": snippet,
                    "matched_group1": "; ".join(g1_in_snippet),
                    "matched_group2": kw2,
                })

# --- Save output ---
result_df = pd.DataFrame(results)
print(f"\nFound {len(result_df)} matching snippets from {result_df['entry_id'].nunique()} unique entries.")

result_df.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")
print(f"Saved CSV: {OUTPUT_CSV}")

result_df_clean = result_df.map(clean_for_excel)
result_df_clean.to_excel(OUTPUT_XLSX, index=False)
print(f"Saved Excel: {OUTPUT_XLSX}")

# --- Quick summary ---
print("\n--- Summary by actor type ---")
print(result_df["type"].value_counts().to_string())

print("\n--- Matched Group 2 keywords ---")
print(result_df["matched_group2"].value_counts().to_string())

print("\nDone.")
