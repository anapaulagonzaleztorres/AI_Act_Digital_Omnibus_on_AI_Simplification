"""
Reliability check — Step 2: compute Cohen's kappa.

Run this once a completed blind sheet comes back. It compares the coder's entries
against the answer key and reports, for `position` and `argument_type` separately:

  - raw percentage agreement
  - Cohen's kappa
  - the Landis & Koch verbal band
  - every disagreement, so they can be inspected and discussed

Usage:
    python3 compute_kappa.py inter_coder
    python3 compute_kappa.py intra_coder

Cohen's kappa in plain language: it asks how often two coders agreed *beyond what
chance alone would produce*. 1.0 is perfect agreement, 0 is no better than guessing.
Landis & Koch (1977) read 0.21-0.40 as fair, 0.41-0.60 moderate, 0.61-0.80 substantial,
and above 0.81 as almost perfect.

Note: kappa is sensitive to how unevenly the categories are spread. When one category
dominates (here, pro_simplification is 65% of the corpus), kappa is pushed down even
when raw agreement is high. Report both numbers, and say so.
"""

import os
import sys

import pandas as pd

# Resolve relative to this script, so the repository works wherever it is unzipped.
HERE = os.path.dirname(os.path.abspath(__file__))
VARIABLES = ["position", "argument_type"]

# The coder codebook writes labels as prose ("anti-simplification", "legal certainty") while
# the answer key stores them as dataset identifiers ("anti_simplification", "legal_certainty").
# Without this, every row scores as a disagreement and kappa comes out at zero.
LABEL_ALIASES = {
    # CODEBOOK_for_coders.md names this category "Improve government"; the dataset and the
    # manuscript tables use improve_governance. Same category, one name.
    "improve_government": "improve_governance",
}

ALLOWED = {
    "position": {
        "pro_simplification", "anti_simplification", "pro_deregulation",
        "anti_deregulation", "neutral_ambivalent",
    },
    "argument_type": {
        "technical_feasibility", "regulatory_coherence", "legal_certainty",
        "rights_protection", "competitiveness", "industry_self_regulation",
        "improve_governance", "inclusive_governance",
    },
}


def normalise(value):
    """Reduce a label to its dataset identifier: 'Legal certainty ' -> 'legal_certainty'."""
    if not isinstance(value, str):
        return value
    cleaned = "_".join(value.strip().lower().replace("-", " ").split())
    return LABEL_ALIASES.get(cleaned, cleaned)


def warn_unrecognised(series, variable, source):
    """Flag values that are not a known label, so a real typo is not normalised into a match."""
    unknown = sorted({v for v in series if isinstance(v, str) and v not in ALLOWED[variable]})
    if unknown:
        print(f"  WARNING: unrecognised {variable} value(s) in the {source}: {unknown}")
        print(f"           these will count as disagreements — check for a typo.")


def cohens_kappa(a, b):
    """Cohen's kappa for two equal-length sequences of labels."""
    a, b = list(a), list(b)
    n = len(a)
    if n == 0:
        raise ValueError("No rows to compare")

    observed = sum(x == y for x, y in zip(a, b)) / n

    labels = set(a) | set(b)
    expected = sum(
        (a.count(label) / n) * (b.count(label) / n) for label in labels
    )

    if expected == 1.0:                       # both coders used a single label
        return observed, float("nan"), expected
    return observed, (observed - expected) / (1 - expected), expected


def band(kappa):
    """Landis & Koch (1977) verbal bands."""
    if kappa != kappa:                        # NaN
        return "undefined (no variation in the labels used)"
    for upper, name in [
        (0.00, "poor"), (0.20, "slight"), (0.40, "fair"),
        (0.60, "moderate"), (0.80, "substantial"),
    ]:
        if kappa <= upper:
            return name
    return "almost perfect"


def main(which):
    key = pd.read_csv(f"{HERE}/KEY_{which}.csv")
    coded = pd.read_excel(f"{HERE}/blind_sheet_{which}.xlsx", sheet_name="code_here")

    coded = coded.rename(columns={
        "position_CODE_HERE": "position_new",
        "argument_type_CODE_HERE": "argument_type_new",
    })

    merged = key.merge(
        coded[["snippet_id", "position_new", "argument_type_new"]],
        on="snippet_id", how="left", validate="one_to_one",
    )

    blank = merged[merged[["position_new", "argument_type_new"]].isna().any(axis=1)]
    if len(blank):
        print(f"WARNING: {len(blank)} row(s) not yet coded — "
              f"snippet_id {list(blank['snippet_id'])}. Excluding them.\n")
        merged = merged.drop(blank.index)

    for var in VARIABLES:
        original = merged[var].map(normalise)
        new = merged[f"{var}_new"].map(normalise)

        print(f"=== {var} ({which}, N = {len(merged)}) ===")
        warn_unrecognised(original, var, "answer key")
        warn_unrecognised(new, var, "returned sheet")

        agree, kappa, expected = cohens_kappa(original, new)
        print(f"  raw agreement      {agree:.1%}  ({int(round(agree * len(merged)))}/{len(merged)})")
        print(f"  expected by chance {expected:.1%}")
        print(f"  Cohen's kappa      {kappa:.3f}  -> {band(kappa)}")

        disagreements = merged[original != new]
        if len(disagreements):
            print(f"  {len(disagreements)} disagreement(s):")
            for _, row in disagreements.iterrows():
                print(f"    snippet {row['snippet_id']}: "
                      f"original '{row[var]}' vs new '{row[f'{var}_new']}'")
        print()

    both = merged[
        (merged["position"].map(normalise) == merged["position_new"].map(normalise))
        & (merged["argument_type"].map(normalise) == merged["argument_type_new"].map(normalise))
    ]
    print(f"Rows where BOTH variables matched: {len(both)}/{len(merged)} "
          f"({len(both) / len(merged):.1%})")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("inter_coder", "intra_coder"):
        sys.exit("Usage: python3 compute_kappa.py [inter_coder|intra_coder]")
    main(sys.argv[1])
