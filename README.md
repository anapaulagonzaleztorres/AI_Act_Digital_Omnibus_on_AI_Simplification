# Replication materials — *AI the Brussels way: Simplifying the (de)regulation?*

Replication data, code and figures for a discourse network analysis of stakeholder feedback to the
European Commission's consultation on the **Digital Omnibus / simplification package**
(Have Your Say initiative 14855, call for evidence September 16 – October 14, 2025).

The study asks how actors used the idea of "regulatory simplification" in relation to three AI Act
regulatory tools — **AI regulatory sandboxes**, **AI standards**, and the **GPAI Code of
Practice** — and compares the resulting discourse with the adopted Digital Omnibus on AI,
Regulation (EU) 2026/1744.

**Method:** Discourse Network Analysis (Leifeld 2016), with AI-assisted, human-adjudicated coding.

> **Citation**
> A. P. Gonzalez Torres, "AI the Brussels way: Simplifying the (de)regulation?",
> *Journal of Computational Law and Legal Technology* (forthcoming). DOI: to be added on publication.

---

## What is here

```
├─ README.md  ·  CODEBOOK.md  ·  LICENSE  ·  LICENSE-DATA
├─ data/           the dataset and the derived statistics tables
├─ code/           the full pipeline, in order
├─ figures/        every figure in the article and its appendices
├─ interactive/    two browsable network graphs
└─ reliability/    the coding session log and the reliability check
```

---

## data/

| File | What it is |
|---|---|
| `eu_feedback_filtered.csv` | **89 snippets** from 45 organisations — every passage that matched the two-group keyword filter, with the matched paragraph and which keywords matched |
| `eu_feedback_coded.csv` | **80 coded rows** — the dataset all results in the paper are computed from, with `regulatory_tool`, `position`, `argument_type` and notes |
| `network_summary.csv` | the structural-properties table reported in the article |
| `centrality_congruence.csv` | weighted degree and betweenness for each of the 42 actors in the congruence network |
| `centrality_conflict.csv` | the same for the conflict network |

`eu_feedback_coded.csv` is the file to use. It deliberately keeps the **pre-merge** argument-type
labels (`competition_harm`, `improve_governance`, `inclusive_governance`), so the two merges
reported in the paper can be undone and inspected. To reproduce the paper's seven categories:

```
competition_harm      -> competitiveness
improve_governance    -> governance
inclusive_governance  -> governance
```

The two centrality files are the source for the actor-level figures quoted in the article — for
instance AI Standards Lab's conflict weighted degree of 41 against 28 for the next-placed actors,
and the eight actors tied at a congruence weighted degree of 39. `network_summary.csv` reports only
the maxima, so these two files are what let a reader check the named-actor claims directly.

### Two notes on the data

**Contact details are redacted.** The keyword filter captured a ±1200-character window around each
match, which in some submissions swept up the document's footer or "authors and contact" block.
Email addresses and telephone numbers in the `matched_paragraph` column have been replaced with
`[email redacted]` and `[phone redacted]`. This affects that column only; `snippet_id`,
`actor_name`, `actor_type`, `regulatory_tool`, `position`, `argument_type` and `notes` are
untouched, and no count, table, network edge or reliability figure in the paper depends on the
redacted text.

**The raw scrape is not included.** The scrape of all 486 consultation entries contains 24
submissions from named private individuals ("EU citizen" / "Non-EU citizen"). None is in this study
— all 24 were removed by the keyword filter, and every one of the 45 analysed actors is an
organisation. Rather than republish personal data, the scraper is provided so the raw file can be
regenerated: run `code/scrape_eu_feedback.py` then `code/enrich_feedback_with_pdfs.py`. The
underlying submissions are published by the Commission at
<https://ec.europa.eu/info/law/better-regulation/have-your-say/initiatives/14855-Simplification-digital-package-and-omnibus/feedback_en>

---

## code/

Run in this order. Steps 1–3 build the dataset; steps 4–5 build the networks.

| Step | Script | Input → output |
|---|---|---|
| 1 | `scrape_eu_feedback.py` | Commission portal → raw entries (Python, Playwright) |
| 1b | `enrich_feedback_with_pdfs.py` | downloads attached PDFs, extracts their text |
| 2 | `extract_keywords.py` | raw entries → `eu_feedback_filtered.csv` (89 snippets) |
| 3 | `build_coded_file.py` | `eu_feedback_filtered.csv` → `eu_feedback_coded.csv` (80 rows) |
| 4 | `step4_networks.R` | coded data → actor–position networks (R) |
| 5 | `step5_dna.R` | coded data → congruence and conflict networks (R) |
| — | `compute_network_stats.py` | coded data → the network statistics reported in the paper |

Every script locates the dataset automatically, whether you keep this folder structure or flatten
it.

### `build_coded_file.py` is the audit trail

Every coding decision is a single line in this script: the snippet index, any split identifier,
whether the row was kept or deleted, the regulatory tool, the position, the argument type, and a
note. Nothing was coded outside it. Reading it end to end shows exactly how 89 retrieved snippets
became 80 coded rows:

- **7 snippets** addressed two regulatory tools and were split into two rows each (→ 14 rows)
- **16 rows** were excluded as duplicates or near-duplicates created by overlapping context windows
- 96 candidate rows − 16 excluded = **80**

### Verification gate

`compute_network_stats.py` refuses to report unless it reproduces **452 congruence edges** and
**167 conflict edges**. If you get different numbers, you are reading the wrong file.

```bash
cd code && python3 compute_network_stats.py     # must print: 452 ... 167 ... PASS
```

---

## figures/

Filenames match the appendix sections in the article.

**Appendix 4 — actor–position networks** (from `step4_networks.R`)
`network_AI_sandbox.png` · `network_AI_standards.png` · `network_GPAI_CoP.png` · `network_overall.png`

**Appendix 5 — congruence networks** (from `step5_dna.R`)
`congruence_AI_sandbox.png` · `congruence_AI_standards.png` · `congruence_GPAI_CoP.png` · `congruence_all.png`

**Appendix 6 — conflict networks** (from `step5_dna.R`)
`conflict_AI_standards.png` · `conflict_GPAI_CoP.png` · `conflict_all.png`

**In the article body:** `network_overall_by_actor_type.png` is Figure 2; `congruence_all.png` and
`conflict_all.png` are Figures 3 and 4. Their subtitles read "452 connections" and "167
connections".

Node colours use the Okabe–Ito colourblind-safe qualitative palette; separation was checked under
simulated deuteranopia and protanopia.

---

## interactive/

Self-contained web pages — no server needed. **Download them and open in a browser**, or use the
hosted versions linked from the article.

| File | Appendix | What you can do |
|---|---|---|
| `step4_network_interactive.html ` | 4.5 | Filter by actor type; dim or hide non-matching actors; click a node to isolate it and its positions |
| `step5_dna_interactive_physics.html ` | 7 | Toggle congruence/conflict; filter by regulatory tool; click a position in the legend to show only actors holding that stance; click a node to isolate its neighbours |

https://anapaulagonzaleztorres.github.io/AI_Act_Digital_Omnibus_on_AI_Simplification/interactive/step4_network_interactive.html

https://anapaulagonzaleztorres.github.io/AI_Act_Digital_Omnibus_on_AI_Simplification/interactive/step5_dna_interactive_physics.html

---

## reliability/

| File | What it is |
|---|---|
| `coding_session_log.md` | The full log of the supervised coding session: what the model was shown, what it proposed, and every correction the author made across the seventeen batches. Local paths and account names are replaced with `<user>` / `<team>`; nothing else is altered |
| `CODEBOOK_for_coders.md` | The blind instrument sent to the independent second coder — see the note below |
| `blind_sheet_inter_coder.xlsx` | The 16-snippet subsample as returned by the second coder |
| `blind_sheet_intra_coder.xlsx` | The author's own blind re-code of a separate 20 snippets |
| `KEY_inter_coder.csv`, `KEY_intra_coder.csv` | The original codes for those two samples (a subset of `eu_feedback_coded.csv`) |
| `compute_kappa.py` | Reproduces all four Cohen's κ values |

```bash
cd reliability
python3 compute_kappa.py inter_coder    # 75.0% / κ=0.508  and  50.0% / κ=0.363
python3 compute_kappa.py intra_coder    # 80.0% / κ=0.684  and  70.0% / κ=0.632
```

Both samples were drawn from the 80-row dataset with a fixed seed before any inspection, and they
are disjoint, so neither check contaminates the other.

The `KEY_*.csv` files record the codes in the seven-category scheme, i.e. with the two merges
applied, while `data/eu_feedback_coded.csv` keeps the pre-merge labels. Comparing the two therefore
shows one apparent difference — snippet 9 is `competitiveness` in the key and `competition_harm` in
the dataset — which is the same code before and after the merge. Use the keys as supplied: they
reproduce the figures above exactly (rebuilding them from the dataset instead gives κ = 0.634 rather
than 0.632 for argument type within coder, with identical raw agreement).

**Two codebooks, and why they differ.** `CODEBOOK.md` (top level) is the codebook as published in
the article: **seven** argument types. `reliability/CODEBOOK_for_coders.md` is the blind instrument
the second coder actually worked from, and it lists **eight**, because it was written before
`improve governance` and `inclusive governance` were merged for reporting. It also deliberately
contains no example quotations, so that nothing could leak the original coding. It is published
unchanged so the reliability figures can be checked against the exact instrument that produced them.

**Reliability as reported in the article.** Between coders: 75.0% agreement (κ = 0.508) on position,
50.0% (κ = 0.363) on argument type, on N = 16. Within coder: 80.0% (κ = 0.684) and 70.0%
(κ = 0.632) on N = 20. Measured on the pro/anti contrast that the networks are actually built from,
agreement is 93.8% (κ = 0.818) between coders and 95.0% (κ = 0.875) within coder, and substituting
the second coder's assignments reproduces the same edge counts. Argument-type disagreements
concentrate on one boundary — technical feasibility versus regulatory coherence — for which
`CODEBOOK.md` states an explicit rule.

---

## Requirements

**Python 3.10+** — `pandas`, `networkx`, `openpyxl`; plus `playwright` and `beautifulsoup4` for
scraping and `pdfminer.six` for PDF extraction.

**R 4.2+** — `igraph`, `ggraph`, `ggplot2`, `visNetwork`, `dplyr`, `tidyr`, `ggnewscale`,
`ggforce`, `patchwork`, `htmlwidgets`.

```bash
pip install pandas networkx openpyxl playwright beautifulsoup4 pdfminer.six
```

---

## Licence

Code is released under the **MIT Licence** (`LICENSE`).
The dataset, derived tables, figures and documentation are released under **CC BY 4.0**
(`LICENSE-DATA`).

The underlying consultation submissions are the work of the organisations that filed them and are
published by the European Commission; the licence here covers the *compilation, coding and
analysis*, not the source texts.
