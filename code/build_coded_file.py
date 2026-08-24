"""
Step 3: Build eu_feedback_coded.csv and eu_feedback_coded.xlsx
Applies all manual coding decisions from the interactive coding session.
"""

import os

import pandas as pd

_HERE = os.path.dirname(os.path.abspath(__file__))


def _find(name):
    """Locate a data file whether the repo is flat or sorted into folders."""
    for cand in (os.path.join(_HERE, name),
                 os.path.join(_HERE, "..", "data", name),
                 os.path.join(_HERE, "data", name)):
        if os.path.exists(cand):
            return os.path.abspath(cand)
    raise FileNotFoundError(
        f"Could not find {name}. Expected it beside this script or in ../data/"
    )


# Load original filtered data
df = pd.read_csv(_find("eu_feedback_filtered.csv"))

# ── Regulatory tool mapping (from matched_group2) ──────────────────────────
tool_map = {
    'harmonised standards': 'AI_standards',
    'AI standards':         'AI_standards',
    'code of practice':     'GPAI_CoP',
    'AI regulatory sandbox':'AI_sandbox',
}

# ── All coding decisions ───────────────────────────────────────────────────
# Each tuple: (original_idx, sub_id, action, regulatory_tool, position, argument_type, notes)
#   sub_id : None = normal row; 'a'/'b' = split
#   action : 'keep' or 'delete'
#   regulatory_tool: overrides the tool_map value for splits; use '' to auto-map

coding = [
    (0,  None, 'keep',   'AI_standards', 'pro_deregulation',   'industry_self_regulation', 'Data Act cloud portability context (Art. 33/35 Data Act), not AI Act — possible false positive'),
    (1,  None, 'keep',   'AI_standards', 'pro_deregulation',   'industry_self_regulation', 'Overlap with #0 — same document, same argument on cloud portability harmonised standards'),
    (2,  None, 'keep',   'AI_standards', 'pro_simplification', 'competitiveness',          ''),
    (3,  None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     ''),
    (4,  None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (5,  None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Overlap with #4 — same document section'),
    (6,  None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     'Harmonised standards refers to open data metadata, not AI Act — likely false positive'),
    (7,  None, 'keep',   'AI_standards', 'neutral_ambivalent', 'inclusive_governance',     ''),
    (8,  None, 'keep',   'GPAI_CoP',     'neutral_ambivalent', 'inclusive_governance',     ''),
    (9,  None, 'keep',   'GPAI_CoP',     'pro_deregulation',   'competition_harm',         ''),
    (10, None, 'keep',   'AI_standards', 'pro_simplification', 'competitiveness',          ''),
    (11, 'a',  'keep',   'GPAI_CoP',     'pro_deregulation',   'regulatory_coherence',     'Split from #11 — CoP argument (promote CoP/self-regulation as compliance pathway)'),
    (11, 'b',  'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Split from #11 — AI standards argument (phase requirements to match standard readiness)'),
    (12, None, 'keep',   'AI_standards', 'anti_simplification','rights_protection',        ''),
    (13, None, 'keep',   'AI_standards', 'anti_simplification','rights_protection',        'Overlap with #12 — same document, same argument'),
    (14, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'CRA context — possible false positive'),
    (15, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (16, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Overlap with #15 — same document'),
    (17, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (18, 'a',  'keep',   'GPAI_CoP',     'pro_simplification', 'technical_feasibility',    'Split from #18 — CoP argument (stop-the-clock until CoP on Art. 50 ready)'),
    (18, 'b',  'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     'Split from #18 — AI standards argument (align CEN CENELEC with international standards)'),
    (19, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'regulatory_coherence',     ''),
    (20, None, 'keep',   'GPAI_CoP',     'pro_deregulation',   'competitiveness',          ''),
    (21, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'legal_certainty',          ''),
    (22, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'regulatory_coherence',     'CoP here refers to Disinformation CoP, not GPAI CoP — likely false positive'),
    (23, None, 'keep',   'GPAI_CoP',     'anti_deregulation',  'rights_protection',        ''),
    (24, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (25, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (26, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (27, None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     ''),
    (28, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (29, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (30, None, 'keep',   'GPAI_CoP',     'anti_simplification','rights_protection',        ''),
    (31, None, 'keep',   'GPAI_CoP',     'anti_deregulation',  'rights_protection',        ''),
    (32, None, 'keep',   'GPAI_CoP',     'neutral_ambivalent', 'legal_certainty',          ''),
    (33, None, 'keep',   'GPAI_CoP',     'anti_simplification','rights_protection',        'Transparency obligations must be enforced without delay or derogation [ex broader context window]'),
    (34, None, 'keep',   'GPAI_CoP',     'anti_deregulation',  'rights_protection',        ''),
    (35, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Harmonised standards refers to MR/CRA machinery context, not AI Act — possible false positive'),
    (36, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'pro_simplification — postpone until standards finalised; suspend fines'),
    (37, None, 'delete', '',             '',                   '',                         'Duplicate of #36 — overlapping context window'),
    (38, None, 'keep',   'AI_sandbox',   'pro_simplification', 'legal_certainty',          ''),
    (39, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (40, None, 'keep',   'AI_standards', 'anti_simplification','rights_protection',        ''),
    (41, None, 'keep',   'AI_standards', 'anti_simplification','legal_certainty',          ''),
    (42, None, 'keep',   'AI_standards', 'anti_simplification','improve_governance',       ''),
    (43, None, 'keep',   'AI_standards', 'pro_simplification', 'legal_certainty',          ''),
    (44, None, 'keep',   'GPAI_CoP',     'anti_simplification','rights_protection',        ''),
    (45, None, 'keep',   'AI_standards', 'pro_simplification', 'legal_certainty',          'Also briefly mentions AI regulatory sandbox — not split as mention too brief'),
    (46, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'regulatory_coherence',     ''),
    (47, None, 'keep',   'GPAI_CoP',     'anti_deregulation',  'rights_protection',        'Near-identical text to #31 (BDZV) and #34 (MVFP) — joint publishers coalition submission'),
    (48, 'a',  'keep',   'GPAI_CoP',     'pro_deregulation',   'legal_certainty',          'Split from #48 — CoP argument (revise systemic risk thresholds; avoid responsibility shifting to finetuners/users)'),
    (48, 'b',  'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Split from #48 — AI standards argument (extend deadlines 24 months; link to harmonised standards)'),
    (49, None, 'keep',   'AI_standards', 'neutral_ambivalent', 'improve_governance',       ''),
    (50, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (51, None, 'delete', '',             '',                   '',                         'Near-duplicate of #50 — overlapping context window'),
    (52, None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     'CRA/NIS-2 cybersecurity standards context, not AI Act — likely false positive'),
    (53, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'CRA harmonised standards timeline, not AI Act — likely false positive'),
    (54, None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     'CRA/RED overlap, not AI Act — likely false positive'),
    (55, None, 'delete', '',             '',                   '',                         'Duplicate of #50 — overlapping context window'),
    (56, None, 'delete', '',             '',                   '',                         'Duplicate of #50 — overlapping context window'),
    (57, None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     ''),
    (58, None, 'delete', '',             '',                   '',                         'Near-duplicate of #57 — overlapping context window'),
    (59, None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     ''),
    (60, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'regulatory_coherence',     ''),
    (61, 'a',  'keep',   'AI_sandbox',   'pro_simplification', 'technical_feasibility',    'Split from #61 — AI sandbox argument (dedicated Occupational Safety and Health focused sandbox streams as safe harbor for SMEs)'),
    (61, 'b',  'keep',   'AI_standards', 'pro_simplification', 'legal_certainty',          'Split from #61 — AI standards argument (mandate Occupational Safety and Health specific harmonised standards for presumption of conformity)'),
    (62, None, 'keep',   'AI_sandbox',   'pro_simplification', 'technical_feasibility',    ''),
    (63, None, 'delete', '',             '',                   '',                         'Near-duplicate of #62 — overlapping context window'),
    (64, 'a',  'keep',   'AI_standards', 'pro_deregulation',   'industry_self_regulation', 'Split from #64 — AI standards argument (limit Commission power to impose Common Specifications; preserve European Standardisation System)'),
    (64, 'b',  'keep',   'GPAI_CoP',     'pro_simplification', 'technical_feasibility',    'Split from #64 — CoP refers specifically to Code of Practice on Art. 50 transparency obligations for generative AI systems; legal specifications not complete before obligations apply'),
    (65, None, 'delete', '',             '',                   '',                         'Near-duplicate of #64 — overlapping context window'),
    (66, None, 'delete', '',             '',                   '',                         'Duplicate of #64b — overlapping context window'),
    (67, None, 'keep',   'GPAI_CoP',     'anti_deregulation',  'competitiveness',          'Inverse use — arguing GPAI rules support EU competitiveness and protect downstream SME deployers'),
    (68, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'CRA/RED certification standards context, not AI Act — likely false positive'),
    (69, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'CRA harmonised standards timeline, not AI Act — likely false positive'),
    (70, None, 'delete', '',             '',                   '',                         'Near-duplicate of #69 — overlapping context window'),
    (71, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (72, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'technical_feasibility',    ''),
    (73, 'a',  'keep',   'GPAI_CoP',     'pro_deregulation',   'legal_certainty',          'Split from #73 — CoP argument (user-oriented CoP; revise systemic risk thresholds; avoid responsibility shifting)'),
    (73, 'b',  'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Split from #73 — AI standards argument (link transition periods to harmonised standard availability)'),
    (74, None, 'keep',   'AI_standards', 'anti_simplification','legal_certainty',          'Agreed deadlines give planning security; delay makes legislation unpredictable — same argument type used inversely against postponement'),
    (75, None, 'keep',   'AI_standards', 'neutral_ambivalent', 'legal_certainty',          'Accepts limited conditional extension (6-12 months) only if national authorities prioritise notified body accreditation; distinct from #74'),
    (76, None, 'delete', '',             '',                   '',                         'Near-duplicate of #75 — overlapping context window'),
    (77, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (78, None, 'delete', '',             '',                   '',                         'Near-duplicate of #77 — overlapping context window'),
    (79, None, 'keep',   'GPAI_CoP',     'pro_simplification', 'competitiveness',          ''),
    (80, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    ''),
    (81, None, 'delete', '',             '',                   '',                         'Near-duplicate of #80 — overlapping context window'),
    (82, 'a',  'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'Split from #82 — AI standards argument (stop-the-clock 36 months after standards; 24-month deadline extension)'),
    (82, 'b',  'keep',   'GPAI_CoP',     'pro_deregulation',   'legal_certainty',          'Split from #82 — CoP argument (revise systemic risk thresholds; avoid responsibility shifting to finetuners)'),
    (83, None, 'delete', '',             '',                   '',                         'Near-duplicate of #82 — overlapping context window'),
    (84, None, 'delete', '',             '',                   '',                         'Near-duplicate of #82 — overlapping context window'),
    (85, None, 'keep',   'AI_standards', 'pro_simplification', 'regulatory_coherence',     ''),
    (86, None, 'delete', '',             '',                   '',                         'Near-duplicate of #85 — overlapping context window'),
    (87, None, 'keep',   'AI_standards', 'pro_simplification', 'technical_feasibility',    'CRA harmonised standards timeline, not AI Act — likely false positive'),
    (88, None, 'delete', '',             '',                   '',                         'Duplicate of #82b — overlapping context window'),
]

# ── Build output rows ──────────────────────────────────────────────────────
rows = []
for (orig_idx, sub_id, action, reg_tool, position, arg_type, notes) in coding:
    if action == 'delete':
        continue  # excluded from clean output

    orig_row = df.iloc[orig_idx].to_dict()

    # Snippet ID
    snippet_id = str(orig_idx) if sub_id is None else f"{orig_idx}{sub_id}"

    # Regulatory tool: use explicit override; fall back to auto-map
    if reg_tool:
        regulatory_tool = reg_tool
    else:
        regulatory_tool = tool_map.get(str(orig_row.get('matched_group2', '')).strip(), '')

    rows.append({
        'snippet_id':       snippet_id,
        'entry_id':         orig_row['entry_id'],
        'date':             orig_row['date'],
        'actor_type':       orig_row['type'],
        'actor_name':       orig_row['name'],
        'country':          orig_row['country'],
        'url':              orig_row['url'],
        'matched_paragraph':orig_row['matched_paragraph'],
        'matched_group1':   orig_row['matched_group1'],
        'matched_group2':   orig_row['matched_group2'],
        'regulatory_tool':  regulatory_tool,
        'position':         position,
        'argument_type':    arg_type,
        'notes':            notes,
    })

coded_df = pd.DataFrame(rows)

# ── Save outputs ───────────────────────────────────────────────────────────
out_base = os.path.join(os.path.dirname(_find("eu_feedback_filtered.csv")), "eu_feedback_coded")

coded_df.to_csv(out_base + '.csv', index=False)

# Strip illegal Excel characters (form feeds, vertical tabs, etc.) from text columns
import re
def clean_for_excel(val):
    if isinstance(val, str):
        return re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', ' ', val)
    return val

excel_df = coded_df.map(clean_for_excel)
excel_df.to_excel(out_base + '.xlsx', index=False)

print(f"Saved {len(coded_df)} coded rows.")
print(f"\nRegulatory tool breakdown:\n{coded_df['regulatory_tool'].value_counts()}")
print(f"\nPosition breakdown:\n{coded_df['position'].value_counts()}")
print(f"\nArgument type breakdown:\n{coded_df['argument_type'].value_counts()}")
