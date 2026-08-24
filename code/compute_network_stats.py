"""
Network statistics for the congruence and conflict discourse networks.

Computes density, modularity with community detection, and degree and betweenness
centrality for the congruence and conflict networks.

VERIFICATION GATE: must reproduce 452 congruence edges and 167 conflict edges.

Run:  python3 compute_network_stats.py
"""

import itertools
from collections import Counter

import os

import networkx as nx
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

SOURCE = _find("eu_feedback_coded.csv")
OUT = os.path.dirname(SOURCE)

EXPECTED_CONGRUENCE = 452
EXPECTED_CONFLICT = 167

PRO = {"pro_simplification", "pro_deregulation"}
ANTI = {"anti_simplification", "anti_deregulation"}

# Display-name shortening, copied from actor_name_map in step5_dna.R
ACTOR_NAME_MAP = {
    "Association française de normalisation (AFNOR)": "AFNOR",
    "Bundesverband der Deutschen Industrie (BDI) / Federation of German Industries": "BDI",
    "Bundesverband der Unternehmen der Künstlichen Intelligenz in Deutschland e.V. (German AI Association)": "German AI Association",
    "CECIMO - European Association of Manufacturing Technologies": "CECIMO",
    "COCIR - European Coordination Committee of the Radiological, Electromedical and healthcare IT Industry": "COCIR",
    "German Newspaper Publishers and Digitalpublishers Association (BDZV)": "BDZV",
    "MVFP Medienverband der freien Presse e.V.": "MVFP",
    "Orgalim - Europe's Technology Industries": "Orgalim",
    "ENSHPO - The European Network of Safety and Health Professional Organizations": "ENSHPO",
    "Ireland - Department of Enterprise, Tourism and Employment": "Ireland - Dep Enterprise, Tourism and Employment",
}


def mode_first_wins(values):
    """Replicates R's mode_val(): most frequent value, ties broken by first
    appearance in the group."""
    counts = Counter(values)
    best = max(counts.values())
    for value in values:                       # preserves order of appearance
        if counts[value] == best:
            return value


def categorise(position):
    if position in PRO:
        return "pro"
    if position in ANTI:
        return "anti"
    return "neutral"


def load_actor_stances():
    df = pd.read_csv(SOURCE)
    assert len(df) == 80, f"Expected 80 rows, got {len(df)}"

    df = df.drop_duplicates(subset="snippet_id")
    df["actor_name"] = df["actor_name"].replace(ACTOR_NAME_MAP)
    # The Czech entry's full string is long and inconsistently whitespaced; match on prefix.
    df.loc[
        df["actor_name"].str.startswith("Ministry of Industry and Trade of the Czech Republic"),
        "actor_name",
    ] = "Czech Rep - Ministry of Industry and Trade"

    stances = (
        df.groupby(["actor_name", "actor_type", "country", "regulatory_tool"],
                   sort=False)["position"]
        .agg(mode_first_wins)
        .reset_index()
    )
    stances["stance_cat"] = stances["position"].map(categorise)
    return df, stances


def build_edges(stances, mode):
    """One edge per actor pair per tool, then aggregated with weight = number of
    tools on which the pair agrees (congruence) or clashes (conflict)."""
    weights = Counter()
    tools_shared = {}

    for tool, block in stances.groupby("regulatory_tool", sort=False):
        cats = dict(zip(block["actor_name"], block["stance_cat"]))
        for a, b in itertools.combinations(block["actor_name"], 2):
            ca, cb = cats[a], cats[b]
            if mode == "congruence":
                hit = ca == cb and ca != "neutral"
            else:
                hit = {ca, cb} == {"pro", "anti"}
            if hit:
                key = tuple(sorted((a, b)))
                weights[key] += 1
                tools_shared.setdefault(key, []).append(tool)

    graph = nx.Graph()
    graph.add_nodes_from(stances["actor_name"].unique())
    for (a, b), weight in weights.items():
        graph.add_edge(a, b, weight=weight, tools=", ".join(tools_shared[(a, b)]))
    return graph


def describe(graph, name, actor_types):
    """Compute and report the structural statistics for one network."""
    active = graph.subgraph([n for n in graph if graph.degree(n) > 0])
    communities = nx.community.greedy_modularity_communities(active, weight="weight")
    modularity = nx.community.modularity(active, communities, weight="weight")

    degree = dict(active.degree(weight="weight"))
    betweenness = nx.betweenness_centrality(active, weight=None, normalized=True)

    print(f"\n{'=' * 66}\n{name}\n{'=' * 66}")
    print(f"  nodes (all actors)          {graph.number_of_nodes()}")
    print(f"  nodes with >=1 edge         {active.number_of_nodes()}")
    print(f"  edges                       {graph.number_of_edges()}")
    print(f"  density (among connected)   {nx.density(active):.3f}")
    print(f"  components                  {nx.number_connected_components(active)}")
    print(f"  modularity                  {modularity:.3f} "
          f"({len(communities)} communities)")

    print("\n  Top 8 by weighted degree:")
    for actor, value in sorted(degree.items(), key=lambda kv: -kv[1])[:8]:
        print(f"    {value:>4}  {actor}  [{actor_types.get(actor, '?')}]")

    print("\n  Top 8 by betweenness centrality:")
    for actor, value in sorted(betweenness.items(), key=lambda kv: -kv[1])[:8]:
        print(f"    {value:.3f}  {actor}  [{actor_types.get(actor, '?')}]")

    print("\n  Communities (by actor type composition):")
    for i, community in enumerate(communities, 1):
        composition = Counter(actor_types.get(a, "?") for a in community)
        print(f"    community {i} (n={len(community)}): "
              + "; ".join(f"{k} {v}" for k, v in composition.most_common()))

    return {
        "network": name,
        "nodes_total": graph.number_of_nodes(),
        "nodes_connected": active.number_of_nodes(),
        "edges": graph.number_of_edges(),
        "density": round(nx.density(active), 3),
        "components": nx.number_connected_components(active),
        "modularity": round(modularity, 3),
        "n_communities": len(communities),
        "top_degree_actor": max(degree, key=degree.get),
        "top_degree_value": max(degree.values()),
        "top_betweenness_actor": max(betweenness, key=betweenness.get),
        "top_betweenness_value": round(max(betweenness.values()), 3),
    }, degree, betweenness


def main():
    df, stances = load_actor_stances()
    actor_types = dict(zip(df["actor_name"], df["actor_type"]))

    print(f"Actors: {stances['actor_name'].nunique()}   "
          f"actor-tool stances: {len(stances)}")

    congruence = build_edges(stances, "congruence")
    conflict = build_edges(stances, "conflict")

    # ── Verification gate ────────────────────────────────────────────────────
    ok = (congruence.number_of_edges() == EXPECTED_CONGRUENCE
          and conflict.number_of_edges() == EXPECTED_CONFLICT)
    print(f"\nGATE  congruence {congruence.number_of_edges()} "
          f"(expected {EXPECTED_CONGRUENCE})   "
          f"conflict {conflict.number_of_edges()} "
          f"(expected {EXPECTED_CONFLICT})   -> {'PASS' if ok else 'FAIL'}")
    if not ok:
        raise SystemExit(
            "Edge counts do not match the published networks. Check that the file "
            "being read is eu_feedback_coded.csv (80 rows, 45 actors)."
        )

    rows = []
    for graph, name in [(congruence, "Congruence network (all tools)"),
                        (conflict, "Conflict network (all tools)")]:
        summary, degree, betweenness = describe(graph, name, actor_types)
        rows.append(summary)
        label = "congruence" if "Congruence" in name else "conflict"
        pd.DataFrame({
            "actor": list(degree),
            "actor_type": [actor_types.get(a, "?") for a in degree],
            "weighted_degree": [degree[a] for a in degree],
            "betweenness": [round(betweenness[a], 4) for a in degree],
        }).sort_values("weighted_degree", ascending=False).to_csv(
            f"{OUT}/centrality_{label}.csv", index=False)

    pd.DataFrame(rows).to_csv(f"{OUT}/network_summary.csv", index=False)
    print(f"\nWrote network_summary.csv and centrality_*.csv to {OUT}")


if __name__ == "__main__":
    main()
