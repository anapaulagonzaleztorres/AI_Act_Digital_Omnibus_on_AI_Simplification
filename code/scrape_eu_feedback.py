#!/usr/bin/env python3
"""
EU Have Your Say - Feedback Scraper
Initiative: Simplification – digital package and omnibus (14855)

Collects all 512 feedback entries and saves them to Excel + CSV.
"""

import time
import re
import pandas as pd
from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup

BASE_URL = (
    "https://ec.europa.eu/info/law/better-regulation/have-your-say/initiatives/"
    "14855-Simplification-digital-package-and-omnibus/feedback_en?p_id=20401"
)
BASE = "https://ec.europa.eu"


def parse_entries(html):
    """Extract all feedback entries from the page HTML."""
    soup = BeautifulSoup(html, "html.parser")
    entries = []

    for article in soup.find_all("article", class_="ecl-content-item"):
        entry = {}

        # --- Date ---
        time_tag = article.find("time")
        if time_tag:
            span = time_tag.find("span")
            entry["date"] = span.get_text(strip=True) if span else time_tag.get_text(strip=True)
        else:
            entry["date"] = ""

        # --- Type (Business association / EU citizen / etc.) ---
        meta_items = article.find_all("li", class_="ecl-content-block__primary-meta-item")
        if len(meta_items) >= 2:
            entry["type"] = meta_items[1].get_text(strip=True)
        else:
            entry["type"] = ""

        # --- Name, Country, URL ---
        link_tag = article.find("a", class_="ecl-link")
        if link_tag:
            href = link_tag.get("href", "")
            entry["url"] = BASE + href if href.startswith("/") else href

            # Name is the direct text; country is in a nested <span>
            country_span = link_tag.find("span")
            if country_span:
                country_text = country_span.get_text(strip=True)
                # Remove country span text from full link text to get name
                full_text = link_tag.get_text(strip=True)
                name = full_text.replace(country_text, "").strip()
                # Clean parentheses from country
                entry["name"] = name
                entry["country"] = country_text.strip("()")
            else:
                entry["name"] = link_tag.get_text(strip=True)
                entry["country"] = ""
        else:
            entry["url"] = ""
            entry["name"] = ""
            entry["country"] = ""

        # --- Text preview ---
        para = article.find("p", class_="feedback-item-paragraph")
        if para:
            span = para.find("span")
            entry["text"] = span.get_text(strip=True) if span else para.get_text(strip=True)
        else:
            entry["text"] = ""

        if entry.get("name"):
            entries.append(entry)

    return entries


def scrape_all_feedback():
    all_entries = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            )
        )
        page = context.new_page()

        print(f"Loading page...")
        page.goto(BASE_URL, wait_until="networkidle", timeout=30000)
        time.sleep(2)

        page_num = 1

        while True:
            print(f"  Scraping page {page_num}...", end=" ", flush=True)

            html = page.content()
            entries = parse_entries(html)
            all_entries.extend(entries)
            print(f"{len(entries)} entries collected (running total: {len(all_entries)})")

            # Find the "Next" pagination button
            next_links = page.locator("a:has-text('Next')").all()
            if not next_links:
                print("  No 'Next' button found — all pages done.")
                break

            # Click next and wait for new content to load
            next_links[0].click()
            page.wait_for_load_state("networkidle")
            time.sleep(1.5)
            page_num += 1

            # Safety limit (52 pages expected)
            if page_num > 60:
                print("  Reached page limit (60). Stopping.")
                break

        browser.close()

    return all_entries


def main():
    print("=" * 55)
    print("EU Feedback Scraper — Initiative 14855")
    print("=" * 55)

    entries = scrape_all_feedback()

    if not entries:
        print("\nNo entries collected. Something went wrong.")
        return

    df = pd.DataFrame(entries, columns=["date", "type", "name", "country", "text", "url"])

    # Save to Excel
    excel_path = "eu_feedback_14855.xlsx"
    df.to_excel(excel_path, index=False)
    print(f"\nSaved {len(entries)} entries to: {excel_path}")

    # Save to CSV (UTF-8 with BOM for Excel compatibility)
    csv_path = "eu_feedback_14855.csv"
    df.to_csv(csv_path, index=False, encoding="utf-8-sig")
    print(f"Also saved to:              {csv_path}")

    print("\nColumns in output:")
    print("  date     — submission date")
    print("  type     — organization type (Business, EU citizen, etc.)")
    print("  name     — name of organization or person")
    print("  country  — country")
    print("  text     — short description/preview")
    print("  url      — link to full detail page (may include PDF)")

    print(f"\nPreview of first 3 entries:")
    print(df[["date", "type", "name", "country"]].head(3).to_string(index=False))


if __name__ == "__main__":
    main()
