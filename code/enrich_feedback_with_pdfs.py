#!/usr/bin/env python3
"""
EU Feedback Enricher
Visits each feedback detail page, downloads the attached PDF (if any),
extracts the full text, and adds it to the existing Excel + CSV files.

Progress is saved after every 10 entries so the script can be safely
interrupted and restarted without losing work.
"""

import re
import io
import time
import json
import pandas as pd
from pathlib import Path
from playwright.sync_api import sync_playwright
from pdfminer.high_level import extract_text as pdf_extract_text
from pdfminer.pdfparser import PDFSyntaxError

# ── Paths ──────────────────────────────────────────────────────────────────────
FOLDER      = Path(__file__).parent / "omnibus_scraper"
INPUT_CSV   = FOLDER / "eu_feedback_14855.csv"
OUTPUT_XLSX = FOLDER / "eu_feedback_14855.xlsx"
OUTPUT_CSV  = FOLDER / "eu_feedback_14855.csv"
PROGRESS    = FOLDER / "enrich_progress.json"   # saves work-in-progress

BASE        = "https://ec.europa.eu"
API_BASE    = f"{BASE}/info/law/better-regulation/api"
INITIATIVE  = "14855"


# ── Helpers ────────────────────────────────────────────────────────────────────

def feedback_id_from_url(url: str) -> str | None:
    """Extract numeric ID from a URL like …/F33103770_en"""
    m = re.search(r'/F(\d+)_en', url)
    return m.group(1) if m else None


def get_attachment_info(ctx, feedback_id: str) -> list[dict]:
    """Call the API to get attachment list for a feedback ID."""
    url = f"{API_BASE}/feedbackById?feedbackId={feedback_id}&initiativeId={INITIATIVE}&language=en"
    try:
        resp = ctx.request.get(url, timeout=15000)
        if resp.status == 200:
            data = resp.json()
            return data.get("attachments", [])
    except Exception:
        pass
    return []


def download_and_extract(ctx, doc_id: str) -> str:
    """Download a PDF by documentId and return its extracted text."""
    url = f"{API_BASE}/download/{doc_id}"
    try:
        resp = ctx.request.get(url, timeout=60000)
        if resp.status == 200:
            body = resp.body()
            if body[:4] == b'%PDF':
                text = pdf_extract_text(io.BytesIO(body))
                # Clean up whitespace
                text = re.sub(r'\n{3,}', '\n\n', text).strip()
                return text
            else:
                return "[Downloaded file was not a PDF]"
    except PDFSyntaxError:
        return "[PDF could not be parsed — may be a scanned image]"
    except Exception as e:
        return f"[Download error: {e}]"
    return ""


def save_progress(done: dict):
    with open(PROGRESS, "w", encoding="utf-8") as f:
        json.dump(done, f, ensure_ascii=False)


def load_progress() -> dict:
    if PROGRESS.exists():
        with open(PROGRESS, encoding="utf-8") as f:
            return json.load(f)
    return {}


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("EU Feedback Enricher — adding full PDF text")
    print("=" * 60)

    # Load existing data
    df = pd.read_csv(INPUT_CSV, encoding="utf-8-sig")
    total = len(df)
    print(f"Loaded {total} entries from {INPUT_CSV.name}")

    # Load previously completed work (so we can resume)
    done = load_progress()
    print(f"Previously completed: {len(done)} entries\n")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            )
        )

        for i, row in df.iterrows():
            url = str(row.get("url", ""))
            fid = feedback_id_from_url(url)

            if not fid:
                done[str(i)] = {"attachment_text": "", "has_attachment": False, "pdf_url": ""}
                continue

            if str(i) in done:
                print(f"  [{i+1}/{total}] {row.get('name','?')[:40]} — already done, skipping")
                continue

            name = str(row.get("name", "?"))[:45]
            print(f"  [{i+1}/{total}] {name}...", end=" ", flush=True)

            attachments = get_attachment_info(context, fid)

            if not attachments:
                print("no attachment")
                done[str(i)] = {"attachment_text": "", "has_attachment": False, "pdf_url": ""}
            else:
                att = attachments[0]          # take the first (usually only) attachment
                doc_id = att.get("documentId", "")
                pdf_url = f"{API_BASE}/download/{doc_id}"
                text = download_and_extract(context, doc_id)
                word_count = len(text.split()) if text and not text.startswith("[") else 0
                print(f"PDF extracted ({word_count} words)")
                done[str(i)] = {
                    "attachment_text": text,
                    "has_attachment": True,
                    "pdf_url": pdf_url,
                }

            # Save progress every 10 entries
            if (i + 1) % 10 == 0:
                save_progress(done)

        browser.close()

    # Final progress save
    save_progress(done)

    # ── Write results back into the DataFrame ──────────────────────────────────
    df["has_attachment"] = False
    df["pdf_url"]        = ""
    df["attachment_text"] = ""

    for idx_str, result in done.items():
        idx = int(idx_str)
        if idx < len(df):
            df.at[idx, "has_attachment"]  = result.get("has_attachment", False)
            df.at[idx, "pdf_url"]         = result.get("pdf_url", "")
            df.at[idx, "attachment_text"] = result.get("attachment_text", "")

    # ── Save outputs ────────────────────────────────────────────────────────────
    df.to_excel(OUTPUT_XLSX, index=False)
    print(f"\nSaved to {OUTPUT_XLSX.name}")

    df.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")
    print(f"Saved to {OUTPUT_CSV.name}")

    with_att  = df["has_attachment"].sum()
    without   = total - with_att
    print(f"\nSummary:")
    print(f"  Entries with PDF attachment:    {with_att}")
    print(f"  Entries with inline text only:  {without}")
    print(f"  Total:                          {total}")

    if PROGRESS.exists():
        PROGRESS.unlink()   # clean up progress file when done
        print("\nProgress file removed — all done!")


if __name__ == "__main__":
    main()
