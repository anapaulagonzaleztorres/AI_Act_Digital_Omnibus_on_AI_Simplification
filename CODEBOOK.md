# Codebook — argument type classification

The codebook as published in the paper (Appendix 8). It describes
`argument_type` in `eu_feedback_coded.csv`.

**Corpus:** 80 coded rows from 45 organisations, Commission consultation initiative 14855,
feedback period 16 September – 14 October 2025. Counts below are of all 80 rows.

---

## How the types were built

Argument types were coded inductively in two sequential passes: first the actor's regulatory
position, then the logical or rhetorical basis used to justify it. **The criterion is the basis of
the justification, not the position**, so the same argument type can appear with opposing
positions — and two do (competitiveness and legal certainty).

Initial codes emerged from the first ~40 snippets and were consolidated as coding proceeded; for
instance "implementation burden" and "missing standards" were merged into technical feasibility.
No new category emerged in the final 40 snippets. **Nine types emerged in total and were
consolidated into the seven reported here.**

Position and argument type were coded in two separate, independent moments, with no rule linking
them. Nothing in this codebook prevents any argument type from appearing with any position.

---

## The seven argument types

| Argument type | n (%) | The actor argues that… |
|---|---|---|
| Technical feasibility | 31 (38.8%) | …the requirement is technically or operationally unworkable as designed; standards do not yet exist, timelines are too short, or compliance would demand structurally impossible steps |
| Regulatory coherence | 14 (17.5%) | …the same obligation appears in several instruments with inconsistent wording, thresholds or timelines, and calls for alignment or removal of duplication |
| Legal certainty | 12 (15.0%) | …the law is too vague or unpredictable, creating compliance uncertainty, and calls for clearer definitions, explicit timelines or binding guidance |
| Rights protection | 10 (12.5%) | …the change would weaken protections for consumers, rightsholders or persons subject to AI systems, invoking fundamental rights, IP, safety or non-discrimination |
| Competitiveness | 6 (7.5%) | …a provision damages competitive position; either EU firms against global competitors, or incumbents against SMEs within the EU market |
| Governance | 4 (5.0%) | …the institution lacks the capacity, resources or authority to discharge its mandate, or participation in standard-setting and governance is too narrow |
| Industry self-regulation | 3 (3.8%) | …industry-led standards or voluntary frameworks are preferable or sufficient alternatives to mandatory requirements |

Counts sum to 80. *Percentages are rounded and therefore sum to 100.1%.*

---

## Positions

| Label | Use when the actor… |
|---|---|
| `pro_simplification` | wants an obligation's *procedural route* eased — delays, phase-ins, streamlined steps, fewer duplicate filings — without arguing the underlying protection should be lower |
| `pro_deregulation` | wants the *substantive level* of obligation or protection reduced or removed |
| `anti_simplification` | opposes easing the procedure, e.g. argues agreed deadlines should hold |
| `anti_deregulation` | opposes lowering the substantive level of protection |
| `neutral_ambivalent` | acknowledges both sides, or raises a request that takes no stance on simplification |

---

## Decision rules for recurring borderline cases

| Boundary | Rule applied |
|---|---|
| **Simplification vs deregulation** | Ask whether the actor seeks a different route to the same obligation, or a smaller obligation. Requests that change only the procedure, sequence or timing by which a requirement is met are simplification; requests that reduce the level of protection or remove a requirement are deregulation. Where a snippet could be read either way it is coded as simplification and flagged. |
| **Regulatory coherence vs technical feasibility** | Ask what the actor wants changed. Where the request is that two regimes be reconciled, it is coherence; where the request is that a timetable move, it is feasibility. |
| **Regulatory coherence vs legal certainty** | Coherence where the concern is duplication or misalignment between instruments; legal certainty where it is the actor's own compliance planning or predictability over time. |

The regulatory coherence / technical feasibility boundary is the hardest in practice: it accounted
for 3 of the 6 argument-type disagreements in the intra-coder check and 2 of the 8 in the
inter-coder check. Across both checks technical feasibility appears in 11 of the 14 argument-type
disagreements and regulatory coherence in 7. That is why the rule is stated explicitly.

---

## Three disclosures

**The competitiveness merge.** Arguments about competitive harm between EU market participants are
coded under `competitiveness` rather than as a separate category. Both variants make the same form
of claim — an appeal to competitive position as grounds for changing a rule — and the internal
variant occurs once in this corpus, too rarely to sustain a separate category. **The distinction
remains recoverable from the published dataset**, where the row is still labelled
`competition_harm`.

**The governance merge.** `improve_governance` (2) and `inclusive_governance` (2) are reported
jointly as **Governance (4)**. Both labels remain in the published dataset.

**Direction is not fixed by category.** Where an argument type appeared with a position opposite to
its typical direction it was recorded, not recoded. Competitiveness appears with
pro-simplification (3), pro-deregulation (2) and anti-deregulation (1) — the last an actor arguing
that the GPAI rules strengthen European competitiveness by pushing obligations up the value chain.
Legal certainty likewise appears on both sides, including invoked against postponement.

---

## Mapping the dataset to this codebook

`eu_feedback_coded.csv` carries the nine pre-merge labels. To reproduce the seven reported here:

```python
merge = {'competition_harm': 'competitiveness',
         'improve_governance': 'governance',
         'inclusive_governance': 'governance'}
df['argument_type'] = df['argument_type'].replace(merge)
```

Reliability figures for both variables are reported in the paper's methods section.
