# =============================================================================
# Step 5: Discourse Network Analysis (DNA)
# EU AI Act Omnibus Feedback
#
# What this script does:
#   1. Loads the same cleaned data as Step 4
#   2. Builds a CONGRUENCE network: connects actors who share the same
#      position on the same regulatory tool (edge weight = # shared stances)
#   3. Builds a CONFLICT network: connects actors who take opposing positions
#      on the same regulatory tool
#   4. Saves 8 static PNG graphs (2 overall + 6 per regulatory tool)
#   5. Saves 1 interactive HTML with toggle, filters, and clickable legend
#   6. Saves 3 summary CSV tables
#   6. Prints key findings to the R console
#
# How to run: Open in RStudio → click Source
#
# ---- NOTE ON rDNA (for future use) ------------------------------------------
# rDNA is the R package for proper Discourse Network Analysis (Leifeld, 2017).
# To use it later:
#   install.packages("rDNA")           # installs the R wrapper
#   # Also download DNA (Java app) from: https://github.com/leifeld/dna
#   library(rDNA)
#   dna_init("path/to/dna-X.Y.Z.jar") # connect R to the Java backend
#   conn <- dna_connection("your_database.dna")  # open a DNA project file
#   # Then use dna_network() to extract congruence/conflict networks
#   # rDNA gives richer control over statement types, agreement operators, etc.
# The manual approach below replicates the core logic without the Java dependency.
# =============================================================================

# ----- 0. Install packages if needed -----------------------------------------
required_pkgs <- c("tidyverse", "igraph", "ggraph", "RColorBrewer", "ggrepel",
                   "visNetwork", "htmlwidgets", "jsonlite", "ggforce")
new_pkgs <- required_pkgs[!required_pkgs %in% installed.packages()[, "Package"]]
if (length(new_pkgs) > 0) {
  message("Installing missing packages: ", paste(new_pkgs, collapse = ", "))
  install.packages(new_pkgs, repos = "https://cloud.r-project.org")
}

library(tidyverse)
library(igraph)
library(ggraph)
library(RColorBrewer)
library(ggrepel)
library(visNetwork)
library(htmlwidgets)
library(jsonlite)
library(ggforce)
library(ggnewscale)   # lets the node colour scale coexist with the hull scale

# ----- 1. Load & clean data --------------------------------------------------
script_dir <- tryCatch(
  dirname(rstudioapi::getSourceEditorContext()$path),
  error = function(e) "."   # repository copy: resolve relative to the working directory
)
find_data <- function(name) {
  # Works whether the repository is flat or sorted into code/ and data/ folders.
  cands <- c(file.path(script_dir, name),
             file.path(script_dir, "..", "data", name),
             file.path(script_dir, "data", name))
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0) stop("Could not find ", name,
                             " beside this script or in ../data/")
  hit[1]
}
data_path  <- find_data("eu_feedback_coded.csv")
out_dir    <- file.path(script_dir, "outputs", "step5")
out_dir_v2 <- file.path(script_dir, "outputs", "step5_v2")
dir.create(out_dir,    showWarnings = FALSE, recursive = TRUE)
dir.create(out_dir_v2, showWarnings = FALSE, recursive = TRUE)

raw <- read_csv(data_path, show_col_types = FALSE)

df <- raw %>%
  select(snippet_id, actor_type, actor_name, country,
         regulatory_tool, position, argument_type) %>%
  distinct(snippet_id, .keep_all = TRUE)

# ── Actor name display mapping ──────────────────────────────────────────────
# Original names in eu_feedback_coded.csv are preserved.
# These short names are used only in visualisation outputs (Steps 4 & 5).
actor_name_map <- c(
  "Association française de normalisation (AFNOR)"                                                                                                                                                                  = "AFNOR",
  "Bundesverband der Deutschen Industrie (BDI) / Federation of German Industries"                                                                                                                                   = "BDI",
  "Bundesverband der Unternehmen der Künstlichen Intelligenz in Deutschland e.V. (German AI Association)"                                                                                                           = "German AI Association",
  "CECIMO - European Association of Manufacturing Technologies"                                                                                                                                                      = "CECIMO",
  "COCIR - European Coordination Committee of the Radiological, Electromedical and healthcare IT Industry"                                                                                                          = "COCIR",
  "German Newspaper Publishers and Digitalpublishers Association (BDZV)"                                                                                                                                            = "BDZV",
  "MVFP Medienverband der freien Presse e.V."                                                                                                                                                                       = "MVFP",
  "Orgalim - Europe's Technology Industries"                                                                                                                                                                        = "Orgalim",
  "ENSHPO - The European Network of Safety and Health Professional Organizations"                                                                                                                                    = "ENSHPO",
  "Ireland - Department of Enterprise, Tourism and Employment"                                                                                                                                                      = "Ireland - Dep Enterprise, Tourism and Employment",
  "Ministry of Industry and Trade of the Czech Republic - this entry represents the official position of the Czech Republic for the section \u201cTargeted adjustments to the Artificial Intelligence Act to ensure the optimal application of the rules" = "Czech Rep - Ministry of Industry and Trade"
)
df <- df %>%
  mutate(actor_name = recode(actor_name, !!!actor_name_map))

message("Rows loaded: ", nrow(df))

# ----- 2. Actor-concept matrix -----------------------------------------------
# Each unique actor-tool-position combination = one "statement"
# We collapse multiple snippets from the same actor on the same tool
# by taking the most common position (mode)
mode_val <- function(x) {
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}

actor_stances <- df %>%
  group_by(actor_name, actor_type, country, regulatory_tool) %>%
  summarise(position = mode_val(position), .groups = "drop")

# ----- 3. Define agreement and opposition ------------------------------------
# Actors who support simplification / lighter rules
pro_positions  <- c("pro_simplification", "pro_deregulation")
# Actors who oppose simplification / want stricter rules
anti_positions <- c("anti_simplification", "anti_deregulation")

categorise <- function(pos) {
  case_when(
    pos %in% pro_positions  ~ "pro",
    pos %in% anti_positions ~ "anti",
    TRUE                    ~ "neutral"
  )
}

actor_stances <- actor_stances %>%
  mutate(stance_cat = categorise(position))

# ----- 4. Build congruence & conflict edge lists -----------------------------
build_pair_edges <- function(data, mode = "congruence") {
  tools <- unique(data$regulatory_tool)

  edge_list <- map_dfr(tools, function(tool) {
    tool_data <- data %>% filter(regulatory_tool == tool)
    actors <- tool_data$actor_name

    if (length(actors) < 2) return(NULL)

    # All pairs
    pairs <- combn(actors, 2, simplify = FALSE)

    map_dfr(pairs, function(pair) {
      a1 <- tool_data %>% filter(actor_name == pair[1]) %>% pull(stance_cat)
      a2 <- tool_data %>% filter(actor_name == pair[2]) %>% pull(stance_cat)

      if (mode == "congruence") {
        # Agree = same non-neutral category
        agreed <- (a1 == a2) & (a1 != "neutral")
        if (agreed) tibble(from = pair[1], to = pair[2], tool = tool, weight = 1)
        else NULL
      } else {
        # Conflict = one is pro, the other is anti
        conflict <- (a1 == "pro" & a2 == "anti") | (a1 == "anti" & a2 == "pro")
        if (conflict) tibble(from = pair[1], to = pair[2], tool = tool, weight = 1)
        else NULL
      }
    })
  })

  # Aggregate: edge weight = number of tools where they agree/conflict
  if (nrow(edge_list) == 0) return(edge_list)

  edge_list %>%
    group_by(from, to) %>%
    summarise(weight = sum(weight), tools = paste(tool, collapse = ", "),
              .groups = "drop")
}

congruence_edges <- build_pair_edges(actor_stances, "congruence")
conflict_edges   <- build_pair_edges(actor_stances, "conflict")

message("Congruence edges: ", nrow(congruence_edges))
message("Conflict edges:   ", nrow(conflict_edges))

# ----- 5. Actor node attributes (for coloring) -------------------------------†
actor_meta <- df %>%
  distinct(actor_name, actor_type, country)

actor_snippet_count <- df %>%
  group_by(actor_name) %>%
  summarise(n_snippets = n(), .groups = "drop")

# Colourblind-safe palette (Okabe & Ito 2008). Checked under simulated deuteranopia and
# protanopia; the closest pair is dE 10.0 apart. Must match step4_networks.R and the JS
# legend below.
actor_type_colors <- c(
  "Business association"                = "#0072B2",  # blue
  "Company/business"                    = "#E69F00",  # orange
  "Non-governmental organisation (NGO)" = "#009E73",  # bluish green
  "Academic/research Institution"       = "#CC79A7",  # reddish purple
  "Public authority"                    = "#D55E00",  # vermillion
  "Consumer organisation"               = "#56B4E9",  # sky blue
  "Other"                               = "#8C6D31"   # brown
)

# Blue family = pro, orange family = anti, grey = neutral. Deliberately shares no hex
# with actor_type_colors, so one colour never carries two meanings in one figure.
position_colors <- c(
  "pro_simplification"  = "#08519C",  # dark blue
  "pro_deregulation"    = "#6BAED6",  # mid blue
  "anti_simplification" = "#A63603",  # dark orange-brown
  "anti_deregulation"   = "#FD8D3C",  # mid orange
  "neutral_ambivalent"  = "#969696"   # grey
)

# ----- 6. Plot helper ---------------------------------------------------------
plot_actor_network <- function(edges, title, file_name, edge_color,
                               stances = NULL, output_dir = out_dir) {
  if (nrow(edges) == 0) {
    message("No edges for: ", title, " — skipping")
    return(invisible(NULL))
  }

  g <- graph_from_data_frame(edges, directed = FALSE)

  # Add actor metadata
  node_names <- V(g)$name
  node_meta  <- actor_meta[match(node_names, actor_meta$actor_name), ]
  V(g)$actor_type <- node_meta$actor_type
  V(g)$country    <- node_meta$country

  node_colors <- actor_type_colors[V(g)$actor_type]
  node_colors[is.na(node_colors)] <- "#BDBDBD"
  V(g)$color <- node_colors

  snippet_meta     <- actor_snippet_count[match(node_names, actor_snippet_count$actor_name), ]
  V(g)$n_snippets  <- ifelse(is.na(snippet_meta$n_snippets), 1, snippet_meta$n_snippets)

  E(g)$width <- E(g)$weight * 1.5

  # Set position attribute for hull layer
  if (!is.null(stances)) {
    pos_lookup    <- setNames(stances$position, stances$actor_name)
    V(g)$position <- pos_lookup[node_names]
  }

  layout_data <- create_layout(g, layout = "kk")

  p <- ggraph(layout_data) +
    geom_edge_link(aes(width = weight, alpha = weight),
                   color = edge_color, show.legend = FALSE) +
    scale_edge_width(range = c(0.5, 3)) +
    scale_edge_alpha(range = c(0.3, 0.9))

  if (!is.null(stances) && any(!is.na(layout_data$position))) {
    hull_data <- layout_data[!is.na(layout_data$position), ]
    p <- p +
      geom_mark_hull(
        data = hull_data,
        aes(x = x, y = y, fill = position, colour = position,
            label = position),
        alpha = 0.25, expand = unit(4, "mm"), radius = unit(4, "mm"), linewidth = 0.75,
        label.fontsize = 9, label.fontface = "bold",
        label.colour = "white", con.size = 0
      ) +
      scale_fill_manual(values = position_colors, name = "Position",
                        na.value = "transparent") +
      scale_colour_manual(values = position_colors, guide = "none",
                          na.value = "transparent") +
      guides(fill = guide_legend(override.aes = list(alpha = 0.7)))
  }

  # Actor type is mapped inside aes() so ggplot builds a scale and therefore a legend.
  # new_scale_colour() keeps this scale separate from the hull position scale above.
  present_actor_types <- intersect(names(actor_type_colors),
                                   unique(na.omit(layout_data$actor_type)))

  p <- p +
    new_scale_colour() +
    geom_node_point(aes(size = n_snippets, colour = actor_type)) +
    scale_colour_manual(
      values   = actor_type_colors,
      breaks   = present_actor_types,
      limits   = present_actor_types,
      name     = "Actor type",
      na.value = "#BDBDBD",
      guide    = guide_legend(order = 1, override.aes = list(size = 4))
    ) +
    scale_size_area(max_size = 10, guide = "none") +
    geom_node_text(aes(label = name), repel = TRUE, size = 2.5,
                   max.overlaps = 25) +
    labs(
      title    = title,
      subtitle = paste(nrow(edges), "connections | Edge thickness = shared tools"),
      # create_layout() above uses layout = "kk", i.e. Kamada-Kawai.
      caption  = "Node size = coded snippets | Layout: Kamada-Kawai"
    ) +
    theme_graph(base_family = "sans") +
    theme(plot.title      = element_text(size = 13, face = "bold"),
          plot.subtitle   = element_text(size = 10),
          legend.position = "right",
          legend.title    = element_text(face = "bold", size = 9),
          legend.text     = element_text(size = 8))

  out_path <- file.path(output_dir, file_name)
  ggsave(out_path, p, width = 12, height = 9, dpi = 150)
  message("Saved: ", out_path)
}

# ----- 6b. Improved plot helper (v2: color legend, edge legend, less clutter) -
plot_actor_network_v2 <- function(edges, title, file_name, edge_color, out_dir) {
  if (nrow(edges) == 0) {
    message("No edges for: ", title, " — skipping"); return(invisible(NULL))
  }
  g <- graph_from_data_frame(edges, directed = FALSE)

  node_names <- V(g)$name
  node_meta  <- actor_meta[match(node_names, actor_meta$actor_name), ]
  V(g)$actor_type <- ifelse(is.na(node_meta$actor_type), "Other", node_meta$actor_type)
  V(g)$degree     <- igraph::degree(g)

  snippet_meta    <- actor_snippet_count[match(V(g)$name, actor_snippet_count$actor_name), ]
  V(g)$n_snippets <- ifelse(is.na(snippet_meta$n_snippets), 1, snippet_meta$n_snippets)

  p <- ggraph(g, layout = "fr") +
    # show.legend = FALSE. In ggplot, TRUE does not mean "give this layer its own
    # legend" — it means "draw a key for this layer in EVERY legend on the plot", which
    # would stamp the edge glyph behind each dot in the Actor type key. FALSE also drops
    # the edge-width legend, which would interpolate fractional values such as 1.25
    # shared tools; two actors can only ever share 1 or 2 of the three tools.
    geom_edge_link(
      aes(width = weight, alpha = weight),
      color = edge_color, show.legend = FALSE
    ) +
    scale_edge_width(range = c(0.5, 4), guide = "none") +
    scale_edge_alpha(range = c(0.3, 0.9), guide = "none") +
    geom_node_point(aes(color = actor_type, size = n_snippets)) +
    scale_size_area(max_size = 10, guide = "none") +
    scale_color_manual(
      values   = actor_type_colors,
      name     = "Actor type",
      na.value = "#BDBDBD"
    ) +
    geom_node_text(
      aes(label = ifelse(degree >= median(degree), name, "")),
      repel = TRUE, size = 2.8, max.overlaps = 20
    ) +
    labs(
      title    = title,
      subtitle = paste(nrow(edges), "connections | Edge thickness = number of shared tools"),
      caption  = "Layout: Fruchterman-Reingold"
    ) +
    theme_graph(base_family = "sans") +
    theme(
      plot.title      = element_text(size = 14, face = "bold"),
      plot.subtitle   = element_text(size = 10),
      legend.position = "right",
      legend.title    = element_text(face = "bold", size = 9),
      legend.text     = element_text(size = 8)
    )

  out_path <- file.path(out_dir, file_name)
  ggsave(out_path, p, width = 14, height = 10, dpi = 150)
  message("Saved v2: ", out_path)
}

# ----- 7. Produce the 2 network PNGs -----------------------------------------
plot_actor_network(congruence_edges,
  title      = "Congruence Network — Actors Sharing Positions (Coalitions)",
  file_name  = "congruence_network.png",
  edge_color = "#4CAF50")

plot_actor_network(conflict_edges,
  title      = "Conflict Network — Actors with Opposing Positions (Polarization)",
  file_name  = "conflict_network.png",
  edge_color = "#F44336")

# ----- 7b. Per-tool static PNGs with position hulls → step5_hulls/ -----------
build_tool_edges <- function(tool_name, mode = "congruence") {
  build_pair_edges(filter(actor_stances, regulatory_tool == tool_name), mode)
}

out_dir_hulls <- file.path(script_dir, "outputs", "step5_hulls")
dir.create(out_dir_hulls, showWarnings = FALSE, recursive = TRUE)

plot_actor_network(congruence_edges,
  title      = "Congruence Network — All Tools",
  file_name  = "congruence_all.png",
  edge_color = "#4CAF50",
  stances    = actor_stances,
  output_dir = out_dir_hulls)

plot_actor_network(conflict_edges,
  title      = "Conflict Network — All Tools",
  file_name  = "conflict_all.png",
  edge_color = "#F44336",
  stances    = actor_stances,
  output_dir = out_dir_hulls)

for (tool in c("AI_standards", "GPAI_CoP", "AI_sandbox")) {
  tool_stances <- actor_stances %>% filter(regulatory_tool == tool)
  plot_actor_network(build_tool_edges(tool, "congruence"),
    title      = paste("Congruence —", tool),
    file_name  = paste0("congruence_", tool, ".png"),
    edge_color = "#4CAF50",
    stances    = tool_stances,
    output_dir = out_dir_hulls)
  plot_actor_network(build_tool_edges(tool, "conflict"),
    title      = paste("Conflict —", tool),
    file_name  = paste0("conflict_", tool, ".png"),
    edge_color = "#F44336",
    stances    = tool_stances,
    output_dir = out_dir_hulls)
}

# ----- 7d. Improved PNGs → step5_v2/ -----------------------------------------
plot_actor_network_v2(congruence_edges,
  title      = "Congruence Network — All Tools",
  file_name  = "congruence_network.png",
  edge_color = "#4CAF50",
  out_dir    = out_dir_v2)

plot_actor_network_v2(conflict_edges,
  title      = "Conflict Network — All Tools",
  file_name  = "conflict_network.png",
  edge_color = "#F44336",
  out_dir    = out_dir_v2)

for (tool in c("AI_standards", "GPAI_CoP", "AI_sandbox")) {
  plot_actor_network_v2(build_tool_edges(tool, "congruence"),
    title      = paste("Congruence —", tool),
    file_name  = paste0("congruence_", tool, ".png"),
    edge_color = "#4CAF50",
    out_dir    = out_dir_v2)
  plot_actor_network_v2(build_tool_edges(tool, "conflict"),
    title      = paste("Conflict —", tool),
    file_name  = paste0("conflict_", tool, ".png"),
    edge_color = "#F44336",
    out_dir    = out_dir_v2)
}

# ----- 7c. Interactive HTML ---------------------------------------------------

# All actors that appear in either network
all_actors_in_edges <- unique(c(
  congruence_edges$from, congruence_edges$to,
  conflict_edges$from,   conflict_edges$to
))

# Dominant position per actor (most common across all tools)
dominant_positions <- actor_stances %>%
  group_by(actor_name) %>%
  summarise(dominant_position = mode_val(position), .groups = "drop")

vis_nodes <- actor_meta %>%
  filter(actor_name %in% all_actors_in_edges) %>%
  left_join(dominant_positions, by = "actor_name") %>%
  mutate(
    id    = actor_name,
    label = actor_name,
    group = actor_type,
    title = paste0("<b>", actor_name, "</b><br/>",
                   "Type: ", actor_type, "<br/>",
                   "Position: ", replace_na(dominant_position, "—"), "<br/>",
                   "Country: ", country),
    color = actor_type_colors[actor_type]
  ) %>%
  distinct(id, .keep_all = TRUE)   # guard against duplicate actor rows
vis_nodes$color[is.na(vis_nodes$color)] <- "#8C6D31"

vis_nodes <- vis_nodes %>%
  left_join(actor_snippet_count, by = "actor_name") %>%
  mutate(size = 10 + replace_na(n_snippets, 1) * 2)

# Edge tables for the widget (start with congruence visible)
vis_edges_cong <- congruence_edges %>%
  mutate(
    value        = weight,
    title        = paste0("Shared tools: ", tools, "<br/>Network: Congruence"),
    tools_col    = tools,
    network_type = "Congruence"
  ) %>%
  select(from, to, value, title, tools_col, network_type)

vis_edges_conf <- conflict_edges %>%
  mutate(
    value        = weight,
    title        = paste0("Opposing on: ", tools, "<br/>Network: Conflict"),
    tools_col    = tools,
    network_type = "Conflict"
  ) %>%
  select(from, to, value, title, tools_col, network_type)

# Embed both edge sets as JSON so JS can toggle without a server
vis_edges_cong <- vis_edges_cong %>% mutate(color = "#4CAF50")
vis_edges_conf <- vis_edges_conf %>% mutate(color = "#F44336")
cong_json <- jsonlite::toJSON(vis_edges_cong, dataframe = "rows")
conf_json <- jsonlite::toJSON(vis_edges_conf, dataframe = "rows")

js_code <- paste0('function(el, x) {
  setTimeout(function() {

    var network = HTMLWidgets.getInstance(el).network;

    // Freeze nodes in place once the initial layout settles
    network.once("stabilized", function() {
      network.setOptions({ physics: { enabled: false } });
    });

    var originalColors = {};
    network.body.data.nodes.forEach(function(n) {
      originalColors[n.id] = n.color;
    });
    var filterMode = "hide";

    // ── Position-stance filter state ────────────────────────────
    // Edit this JavaScript here, not in the generated HTML: the HTML is rebuilt every
    // time this script is sourced.
    var activePosition      = null;   // selected stance label, null = none selected
    var activePositionRow   = null;   // the highlighted legend row element
    var dominantPositionMap = {};     // node.id -> node.dominant_position
    network.body.data.nodes.forEach(function(n) {
      if (n.dominant_position) dominantPositionMap[n.id] = n.dominant_position;
    });

    // ── Embedded edge data ──────────────────────────────────────
    var congEdges = ', cong_json, ';
    var confEdges = ', conf_json, ';
    var currentType = "Congruence";
    var currentTool = "All";

    function filterEdges() {
      var edges = currentType === "Congruence" ? congEdges : confEdges;
      if (currentTool === "All") return edges;
      return edges.filter(function(e) {
        return e.tools_col.indexOf(currentTool) !== -1;
      });
    }

    // Show only actors whose dominant stance is activePosition, plus the actors they
    // are connected to under the current edge filter (needed for conflict edges, where
    // the opposing side would otherwise vanish and leave dangling links).
    function applyPositionFilter() {
      var filtered = filterEdges();
      var matching = {};
      network.body.data.nodes.forEach(function(n) {
        if (dominantPositionMap[n.id] === activePosition) matching[n.id] = true;
      });
      var neighbours = {};
      filtered.forEach(function(e) {
        if (matching[e.from]) neighbours[e.to]   = true;
        if (matching[e.to])   neighbours[e.from] = true;
      });
      var updates = [];
      network.body.data.nodes.forEach(function(n) {
        updates.push({ id: n.id, hidden: !matching[n.id] && !neighbours[n.id] });
      });
      network.body.data.nodes.update(updates);
    }

    function clearPositionFilter() {
      activePosition = null;
      if (activePositionRow) {
        activePositionRow.style.background = "";
        activePositionRow = null;
      }
      network.body.data.nodes.update(
        network.body.data.nodes.get().map(function(n) { return { id: n.id, hidden: false }; })
      );
    }

    function refreshNetwork() {
      var filtered = filterEdges();
      network.body.data.edges.clear();
      network.body.data.edges.add(filtered);
      network.setOptions({ physics: { enabled: false } });

      var updates = [];
      if (currentTool === "All") {
        network.body.data.nodes.forEach(function(n) {
          updates.push({ id: n.id, color: originalColors[n.id], hidden: false });
        });
      } else {
        var visible = {};
        filtered.forEach(function(e) { visible[e.from] = true; visible[e.to] = true; });
        network.body.data.nodes.forEach(function(n) {
          if (visible[n.id]) {
            updates.push({ id: n.id, color: originalColors[n.id], hidden: false });
          } else if (filterMode === "dim") {
            updates.push({ id: n.id,
              color: { background: "#e0e0e0", border: "#cccccc",
                       highlight: { background: "#e0e0e0", border: "#cccccc" } },
              hidden: false });
          } else {
            updates.push({ id: n.id, hidden: true });
          }
        });
      }
      network.body.data.nodes.update(updates);
      // Re-apply the stance filter so it survives a tool / edge-type change
      if (activePosition !== null) { applyPositionFilter(); }
    }

    // ── Control panel (top-left) ────────────────────────────────
    var panel = document.createElement("div");
    panel.style.cssText =
      "position:absolute;top:100px;left:40px;z-index:20;" +
      "background:rgba(255,255,255,0.96);padding:12px 16px;" +
      "border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.13);" +
      "font-family:Arial,sans-serif;min-width:200px;";

    // --- Network-type toggle ---
    var lbl1 = document.createElement("div");
    lbl1.textContent = "Network type:";
    lbl1.style.cssText =
      "font-size:11px;font-weight:bold;color:#555;" +
      "text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px;";
    panel.appendChild(lbl1);

    var btnRow = document.createElement("div");
    btnRow.style.cssText = "display:flex;gap:6px;margin-bottom:12px;";

    function makeBtn(text, active, activeColor) {
      var btn = document.createElement("button");
      btn.textContent = text;
      btn.style.cssText =
        "padding:5px 12px;font-size:12px;border-radius:4px;cursor:pointer;" +
        "border:1px solid #ccc;font-family:Arial,sans-serif;";
      if (active) {
        btn.style.background   = activeColor;
        btn.style.color        = "white";
        btn.style.borderColor  = activeColor;
      } else {
        btn.style.background = "white";
        btn.style.color      = "#333";
      }
      return btn;
    }

    var btnCong = makeBtn("Congruence", true,  "#4CAF50");
    var btnConf = makeBtn("Conflict",   false, "#F44336");

    btnCong.addEventListener("click", function() {
      currentType = "Congruence";
      btnCong.style.background  = "#4CAF50";
      btnCong.style.color       = "white";
      btnCong.style.borderColor = "#4CAF50";
      btnConf.style.background  = "white";
      btnConf.style.color       = "#333";
      btnConf.style.borderColor = "#ccc";
      refreshNetwork();
    });

    btnConf.addEventListener("click", function() {
      currentType = "Conflict";
      btnConf.style.background  = "#F44336";
      btnConf.style.color       = "white";
      btnConf.style.borderColor = "#F44336";
      btnCong.style.background  = "white";
      btnCong.style.color       = "#333";
      btnCong.style.borderColor = "#ccc";
      refreshNetwork();
    });

    btnRow.appendChild(btnCong);
    btnRow.appendChild(btnConf);
    panel.appendChild(btnRow);

    // --- Regulatory tool dropdown ---
    var lbl2 = document.createElement("div");
    lbl2.textContent = "Regulatory tool:";
    lbl2.style.cssText =
      "font-size:11px;font-weight:bold;color:#555;" +
      "text-transform:uppercase;letter-spacing:0.05em;margin-bottom:6px;";
    panel.appendChild(lbl2);

    var sel = document.createElement("select");
    sel.style.cssText =
      "width:100%;padding:5px 8px;font-size:12px;" +
      "border:1px solid #ccc;border-radius:4px;" +
      "font-family:Arial,sans-serif;cursor:pointer;";

    ["All", "AI_standards", "GPAI_CoP", "AI_sandbox"].forEach(function(t) {
      var opt = document.createElement("option");
      opt.value       = t;
      opt.textContent = t === "All" ? "All tools" : t;
      sel.appendChild(opt);
    });

    sel.addEventListener("change", function() {
      currentTool = this.value;
      refreshNetwork();
    });
    panel.appendChild(sel);

    var modeLbl = document.createElement("div");
    modeLbl.textContent = "Others:";
    modeLbl.style.cssText =
      "font-size:11px;font-weight:bold;color:#555;text-transform:uppercase;" +
      "letter-spacing:0.05em;margin-top:10px;margin-bottom:5px;";
    panel.appendChild(modeLbl);

    var modeRow = document.createElement("div");
    modeRow.style.cssText = "display:flex;gap:6px;";

    function makeToggleBtn(text, isActive) {
      var btn = document.createElement("button");
      btn.textContent = text;
      btn.style.cssText =
        "flex:1;padding:4px 0;font-size:11px;border-radius:4px;cursor:pointer;" +
        "font-family:Arial,sans-serif;border:1px solid #ccc;";
      btn.style.background = isActive ? "#4E79A7" : "white";
      btn.style.color      = isActive ? "white"   : "#333";
      return btn;
    }

    var btnDim  = makeToggleBtn("Dim",  false);
    var btnHide = makeToggleBtn("Hide", true);

    btnDim.addEventListener("click", function() {
      filterMode = "dim";
      btnDim.style.background  = "#4E79A7"; btnDim.style.color  = "white";
      btnHide.style.background = "white";   btnHide.style.color = "#333";
      refreshNetwork();
    });
    btnHide.addEventListener("click", function() {
      filterMode = "hide";
      btnHide.style.background = "#4E79A7"; btnHide.style.color = "white";
      btnDim.style.background  = "white";   btnDim.style.color  = "#333";
      refreshNetwork();
    });

    modeRow.appendChild(btnDim);
    modeRow.appendChild(btnHide);
    panel.appendChild(modeRow);

    el.appendChild(panel);

    // ── Navigation buttons ──────────────────────────────────────
    var nav = el.querySelector(".vis-navigation");
    if (nav) {
      nav.style.cssText =
        "position:absolute;top:220px;left:12px;right:auto;bottom:auto;" +
        "width:120px;height:120px;background:rgba(255,255,255,0.93);" +
        "border-radius:8px;box-shadow:0 2px 6px rgba(0,0,0,0.15);z-index:10;";

      var layout = {
        "vis-up":          { top:  5, left: 43 },
        "vis-left":        { top: 43, left:  5 },
        "vis-down":        { top: 43, left: 43 },
        "vis-right":       { top: 43, left: 81 },
        "vis-zoomIn":      { top: 81, left:  5 },
        "vis-zoomOut":     { top: 81, left: 43 },
        "vis-zoomExtends": { top: 81, left: 81 }
      };
      Object.keys(layout).forEach(function(cls) {
        var btn = nav.querySelector("." + cls);
        if (!btn) return;
        btn.style.cssText =
          "position:absolute;" +
          "top:"  + layout[cls].top  + "px;" +
          "left:" + layout[cls].left + "px;" +
          "right:auto;bottom:auto;width:30px;height:30px;" +
          "border-radius:50%;cursor:pointer;" +
          "background-color:#e8f5e9;border:1px solid #a5d6a7;";
      });
    }

    // ── Legend panel (top-right, clickable) ─────────────────────
    // Must stay in sync with actor_type_colors in the R above.
    var actorTypes = [
      { label: "Business association",                color: "#0072B2" },
      { label: "Company/business",                    color: "#E69F00" },
      { label: "Non-governmental organisation (NGO)", color: "#009E73" },
      { label: "Academic/research Institution",       color: "#CC79A7" },
      { label: "Public authority",                    color: "#D55E00" },
      { label: "Consumer organisation",               color: "#56B4E9" },
      { label: "Other",                               color: "#8C6D31" }
    ];

    function legendHeader(text) {
      var h = document.createElement("div");
      h.style.cssText =
        "font-size:11px;font-weight:bold;letter-spacing:0.06em;" +
        "color:#555;font-family:Arial,sans-serif;text-transform:uppercase;" +
        "margin-bottom:8px;border-bottom:1px solid #e0e0e0;padding-bottom:4px;";
      h.textContent = text;
      return h;
    }

    function legendRow(color, label) {
      var row = document.createElement("div");
      row.style.cssText =
        "display:flex;align-items:center;margin-bottom:5px;" +
        "cursor:pointer;padding:2px 4px;border-radius:3px;";
      row.title = "Click to highlight " + label;

      var dot = document.createElement("span");
      dot.style.cssText =
        "width:13px;height:13px;border-radius:50%;background:" + color +
        ";flex-shrink:0;margin-right:8px;display:inline-block;";

      var txt = document.createElement("span");
      txt.style.cssText = "font-size:12px;color:#333;font-family:Arial,sans-serif;";
      txt.textContent   = label;

      row.appendChild(dot);
      row.appendChild(txt);

      row.addEventListener("click", function() {
        var nodeIds = [];
        network.body.data.nodes.forEach(function(n) {
          if (n.group === label) nodeIds.push(n.id);
        });
        network.selectNodes(nodeIds);
      });
      row.addEventListener("mouseenter", function() { row.style.background = "#f5f5f5"; });
      row.addEventListener("mouseleave", function() { row.style.background = "transparent"; });
      return row;
    }

    // Position-stance rows behave differently from actor-type rows: clicking one
    // FILTERS the network to that stance rather than selecting nodes. Clicking the
    // same row again, or the "all positions" row, clears the filter.
    function legendRowPosition(color, label) {
      var row = document.createElement("div");
      row.style.cssText =
        "display:flex;align-items:center;margin-bottom:5px;" +
        "cursor:pointer;padding:2px 4px;border-radius:3px;";
      row.title = "Click to show only " + label;

      var dot = document.createElement("span");
      dot.style.cssText =
        "width:13px;height:13px;border-radius:50%;background:" + color +
        ";flex-shrink:0;margin-right:8px;display:inline-block;";

      var txt = document.createElement("span");
      txt.style.cssText = "font-size:12px;color:#333;font-family:Arial,sans-serif;";
      txt.textContent   = label;

      row.appendChild(dot);
      row.appendChild(txt);

      row.addEventListener("click", function() {
        if (activePosition === label) {
          clearPositionFilter();
        } else {
          if (activePositionRow) activePositionRow.style.background = "";
          activePosition    = label;
          activePositionRow = row;
          row.style.background = "#e8e8e8";
          applyPositionFilter();
        }
      });
      return row;
    }

    var legendPanel = document.createElement("div");
    legendPanel.style.cssText =
      "position:absolute;top:14px;right:14px;" +
      "background:rgba(255,255,255,0.96);padding:14px 18px;" +
      "border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.13);" +
      "z-index:10;min-width:235px;";

    legendPanel.appendChild(legendHeader("Actor Type (click to highlight)"));
    actorTypes.forEach(function(a) { legendPanel.appendChild(legendRow(a.color, a.label)); });

    var positionStances = [
      { label: "pro_simplification",  color: "#08519C" },
      { label: "pro_deregulation",    color: "#6BAED6" },
      { label: "anti_simplification", color: "#A63603" },
      { label: "anti_deregulation",   color: "#FD8D3C" },
      { label: "neutral_ambivalent",  color: "#969696" }
    ];

    var spacer = document.createElement("div");
    spacer.style.cssText = "margin-top:10px;";
    legendPanel.appendChild(spacer);
    legendPanel.appendChild(legendHeader("Position Stance (click to filter)"));

    // "all positions" reset row — the pie swatch must list the five position_colors
    // above in the same order. Update both together.
    var allRow = document.createElement("div");
    allRow.style.cssText =
      "display:flex;align-items:center;margin-bottom:5px;" +
      "cursor:pointer;padding:2px 4px;border-radius:3px;";
    allRow.title = "Clear the stance filter";
    var allDot = document.createElement("span");
    allDot.style.cssText =
      "width:13px;height:13px;border-radius:50%;flex-shrink:0;margin-right:8px;" +
      "display:inline-block;background:conic-gradient(" +
      "#08519C 0deg 72deg,#6BAED6 72deg 144deg,#A63603 144deg 216deg," +
      "#FD8D3C 216deg 288deg,#969696 288deg 360deg);";
    var allTxt = document.createElement("span");
    allTxt.style.cssText = "font-size:12px;color:#333;font-family:Arial,sans-serif;";
    allTxt.textContent   = "all positions";
    allRow.appendChild(allDot);
    allRow.appendChild(allTxt);
    allRow.addEventListener("click", function() { clearPositionFilter(); });
    legendPanel.appendChild(allRow);

    positionStances.forEach(function(p) {
      legendPanel.appendChild(legendRowPosition(p.color, p.label));
    });

    el.appendChild(legendPanel);

    // ── Node-click: hide non-connected nodes ────────────────────────────────────
    var clickedNodeId = null;
    network.on("click", function(params) {
      if (params.nodes.length > 0) {
        clickedNodeId = params.nodes[0];
        var connected = network.getConnectedNodes(clickedNodeId);
        connected.push(clickedNodeId);
        var updates = [];
        network.body.data.nodes.forEach(function(n) {
          updates.push({ id: n.id, hidden: connected.indexOf(n.id) === -1 });
        });
        network.body.data.nodes.update(updates);
      } else if (clickedNodeId !== null) {
        clickedNodeId = null;
        refreshNetwork();   // restore dropdown filter state
      }
    });
    // ── END node-click ───────────────────────────────────────────────────────────

  }, 950);
}
')

vis_html <- visNetwork(vis_nodes, vis_edges_cong,
  main    = list(text  = "EU AI Act Omnibus — Discourse Network Analysis",
                 style = "font-family:Arial,sans-serif;font-size:20px;font-weight:bold;color:#222;"),
  submain = list(text  = "Toggle Congruence / Conflict &nbsp;·&nbsp; Filter by tool &nbsp;·&nbsp; Click legend to highlight",
                 style = "font-family:Arial,sans-serif;font-size:12px;color:#888;"),
  width = "100%", height = "94vh") %>%
  visGroups(groupname = "Business association",                color = "#0072B2") %>%
  visGroups(groupname = "Company/business",                    color = "#E69F00") %>%
  visGroups(groupname = "Non-governmental organisation (NGO)", color = "#009E73") %>%
  visGroups(groupname = "Academic/research Institution",       color = "#CC79A7") %>%
  visGroups(groupname = "Public authority",                    color = "#D55E00") %>%
  visGroups(groupname = "Consumer organisation",               color = "#56B4E9") %>%
  visGroups(groupname = "Other",                               color = "#8C6D31") %>%
  visOptions(
    highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE)
  ) %>%
  visPhysics(
    solver           = "forceAtlas2Based",
    forceAtlas2Based = list(gravitationalConstant = -120, springLength = 220,
                            springConstant = 0.05, damping = 0.9),
    stabilization    = list(enabled = TRUE, iterations = 300)
  ) %>%
  visNodes(font   = list(size = 13, face = "Arial", color = "#333333"),
           shadow = list(enabled = TRUE, size = 4)) %>%
  visEdges(color  = list(color = "#4CAF50", highlight = "#2E7D32"),
           smooth = list(type = "continuous"), width = 1.5) %>%
  visInteraction(
    navigationButtons = TRUE,
    zoomView          = TRUE,
    zoomSpeed         = 0.25,
    dragView          = TRUE,
    hover             = TRUE,
    tooltipDelay      = 80
  ) %>%
  htmlwidgets::onRender(js_code)

tryCatch({
  message("Building interactive HTML...")
  saveWidget(vis_html,
             normalizePath(file.path(out_dir, "dna_interactive_v2.html"), mustWork = FALSE),
             selfcontained = TRUE)
  message("Saved interactive HTML v2: ", file.path(out_dir, "dna_interactive_v2.html"))
}, error = function(e) {
  message("ERROR generating HTML: ", conditionMessage(e))
})

# ── Build hull JS for physics variant ────────────────────────────────────────
node_pos_json <- jsonlite::toJSON(
  setNames(replace_na(vis_nodes$dominant_position, "neutral_ambivalent"), vis_nodes$id),
  auto_unbox = TRUE
)

hull_js <- paste0('
    // ── Convex hull shading by position ──────────────────────────────────────
    var nodePositionMap = ', node_pos_json, ';
    var hullColors = {
      "pro_simplification":  "#08519C",
      "pro_deregulation":    "#6BAED6",
      "anti_simplification": "#A63603",
      "anti_deregulation":   "#FD8D3C"
    };

    function convexHull(pts) {
      if (pts.length < 2) return pts;
      pts = pts.slice().sort(function(a,b){ return a.x - b.x || a.y - b.y; });
      var lower = [], upper = [];
      for (var i = 0; i < pts.length; i++) {
        while (lower.length >= 2) {
          var l=lower[lower.length-2], m=lower[lower.length-1], r=pts[i];
          if ((m.x-l.x)*(r.y-l.y)-(m.y-l.y)*(r.x-l.x) <= 0) lower.pop(); else break;
        }
        lower.push(pts[i]);
      }
      for (var i = pts.length-1; i >= 0; i--) {
        while (upper.length >= 2) {
          var l=upper[upper.length-2], m=upper[upper.length-1], r=pts[i];
          if ((m.x-l.x)*(r.y-l.y)-(m.y-l.y)*(r.x-l.x) <= 0) upper.pop(); else break;
        }
        upper.push(pts[i]);
      }
      lower.pop(); upper.pop();
      return lower.concat(upper);
    }

    function drawHulls(ctx) {
      var allPos = network.getPositions();
      var groups = {};
      network.body.data.nodes.forEach(function(n) {
        if (n.hidden) return;
        var pos = nodePositionMap[n.id];
        if (!pos || !hullColors[pos]) return;
        if (!groups[pos]) groups[pos] = [];
        if (allPos[n.id]) groups[pos].push(allPos[n.id]);
      });

      Object.keys(groups).forEach(function(pos) {
        var pts = groups[pos];
        if (pts.length === 0) return;
        var color = hullColors[pos];
        var pad = 40;
        ctx.save();
        ctx.fillStyle = color + "28";
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 3]);

        if (pts.length === 1) {
          ctx.beginPath();
          ctx.arc(pts[0].x, pts[0].y, pad, 0, 2*Math.PI);
          ctx.fill(); ctx.stroke();
        } else if (pts.length === 2) {
          var dx=pts[1].x-pts[0].x, dy=pts[1].y-pts[0].y;
          var len=Math.sqrt(dx*dx+dy*dy)||1;
          var nx=-dy/len*pad, ny=dx/len*pad;
          ctx.beginPath();
          ctx.moveTo(pts[0].x+nx, pts[0].y+ny);
          ctx.lineTo(pts[1].x+nx, pts[1].y+ny);
          ctx.arc(pts[1].x, pts[1].y, pad, Math.atan2(ny,nx), Math.atan2(-ny,-nx), false);
          ctx.lineTo(pts[0].x-nx, pts[0].y-ny);
          ctx.arc(pts[0].x, pts[0].y, pad, Math.atan2(-ny,-nx), Math.atan2(ny,nx), false);
          ctx.closePath();
          ctx.fill(); ctx.stroke();
        } else {
          var hull = convexHull(pts);
          var cx=hull.reduce(function(s,p){return s+p.x;},0)/hull.length;
          var cy=hull.reduce(function(s,p){return s+p.y;},0)/hull.length;
          var exp=hull.map(function(p){
            var dx=p.x-cx, dy=p.y-cy, len=Math.sqrt(dx*dx+dy*dy)||1;
            return {x:p.x+dx/len*pad, y:p.y+dy/len*pad};
          });
          ctx.beginPath();
          ctx.moveTo(exp[0].x, exp[0].y);
          for (var i=1;i<exp.length;i++) ctx.lineTo(exp[i].x, exp[i].y);
          ctx.closePath();
          ctx.fill(); ctx.stroke();
        }

        var minY=Math.min.apply(null,pts.map(function(p){return p.y;}));
        var labelX=pts.reduce(function(s,p){return s+p.x;},0)/pts.length;
        ctx.setLineDash([]);
        ctx.fillStyle = color;
        ctx.font = "bold 13px Arial";
        ctx.textAlign = "center";
        ctx.fillText(pos.replace(/_/g," "), labelX, minY - pad - 6);
        ctx.restore();
      });
    }

    network.on("afterDrawing", function(ctx) { drawHulls(ctx); });
    // ── END hull drawing ──────────────────────────────────────────────────────
')

js_parts <- strsplit(js_code, "  }, 950);\n}", fixed = TRUE)[[1]]
js_code_physics <- paste0(js_parts[1], hull_js, "  }, 950);\n}", js_parts[2])

# ── Variant A: tighter physics (clusters pulled closer together) ──────────────
vis_html_physics <- visNetwork(vis_nodes, vis_edges_cong,
  main    = list(text  = "EU AI Act Omnibus — Discourse Network Analysis",
                 style = "font-family:Arial,sans-serif;font-size:20px;font-weight:bold;color:#222;"),
  submain = list(text  = "Toggle Congruence / Conflict &nbsp;·&nbsp; Filter by tool &nbsp;·&nbsp; Click legend to highlight",
                 style = "font-family:Arial,sans-serif;font-size:12px;color:#888;"),
  width = "100%", height = "94vh") %>%
  visGroups(groupname = "Business association",                color = "#0072B2") %>%
  visGroups(groupname = "Company/business",                    color = "#E69F00") %>%
  visGroups(groupname = "Non-governmental organisation (NGO)", color = "#009E73") %>%
  visGroups(groupname = "Academic/research Institution",       color = "#CC79A7") %>%
  visGroups(groupname = "Public authority",                    color = "#D55E00") %>%
  visGroups(groupname = "Consumer organisation",               color = "#56B4E9") %>%
  visGroups(groupname = "Other",                               color = "#8C6D31") %>%
  visOptions(highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE)) %>%
  visPhysics(
    solver           = "forceAtlas2Based",
    forceAtlas2Based = list(gravitationalConstant = -40, springLength = 80,
                            springConstant = 0.2, damping = 0.9),
    stabilization    = list(enabled = TRUE, iterations = 500)
  ) %>%
  visNodes(font   = list(size = 13, face = "Arial", color = "#333333"),
           shadow = list(enabled = TRUE, size = 4)) %>%
  visEdges(color  = list(color = "#4CAF50", highlight = "#2E7D32"),
           smooth = list(type = "continuous"), width = 1.5) %>%
  visInteraction(
    navigationButtons = TRUE, zoomView = TRUE, zoomSpeed = 0.25,
    dragView = TRUE, hover = TRUE, tooltipDelay = 80
  ) %>%
  htmlwidgets::onRender(js_code_physics)


tryCatch({
  message("Building tight-physics HTML...")
  saveWidget(vis_html_physics,
             normalizePath(file.path(out_dir, "dna_interactive_physics.html"), mustWork = FALSE),
             selfcontained = TRUE)
  message("Saved: dna_interactive_physics.html")
}, error = function(e) {
  message("ERROR generating physics HTML: ", conditionMessage(e))
})

# ── Variant B: circular layout (nodes fixed in a ring, no physics) ────────────
# Compute circle positions using igraph
all_node_ids <- vis_nodes$id
g_circle <- make_empty_graph(n = length(all_node_ids), directed = FALSE)
V(g_circle)$name <- all_node_ids
coords <- layout_in_circle(g_circle)
scale_factor <- 800

vis_nodes_circle <- vis_nodes %>%
  mutate(
    x      = coords[match(id, all_node_ids), 1] * scale_factor,
    y      = coords[match(id, all_node_ids), 2] * scale_factor,
    physics = FALSE
  )

vis_html_circle <- visNetwork(vis_nodes_circle, vis_edges_cong,
  main    = list(text  = "EU AI Act Omnibus — Discourse Network Analysis (Circular Layout)",
                 style = "font-family:Arial,sans-serif;font-size:20px;font-weight:bold;color:#222;"),
  submain = list(text  = "Toggle Congruence / Conflict &nbsp;·&nbsp; Filter by tool &nbsp;·&nbsp; Click legend to highlight",
                 style = "font-family:Arial,sans-serif;font-size:12px;color:#888;"),
  width = "100%", height = "94vh") %>%
  visGroups(groupname = "Business association",                color = "#0072B2") %>%
  visGroups(groupname = "Company/business",                    color = "#E69F00") %>%
  visGroups(groupname = "Non-governmental organisation (NGO)", color = "#009E73") %>%
  visGroups(groupname = "Academic/research Institution",       color = "#CC79A7") %>%
  visGroups(groupname = "Public authority",                    color = "#D55E00") %>%
  visGroups(groupname = "Consumer organisation",               color = "#56B4E9") %>%
  visGroups(groupname = "Other",                               color = "#8C6D31") %>%
  visOptions(highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE)) %>%
  visPhysics(enabled = FALSE) %>%
  visNodes(font   = list(size = 13, face = "Arial", color = "#333333"),
           shadow = list(enabled = TRUE, size = 4)) %>%
  visEdges(color  = list(color = "#4CAF50", highlight = "#2E7D32"),
           smooth = list(type = "curvedCW", roundness = 0.2), width = 1.5) %>%
  visInteraction(
    navigationButtons = TRUE, zoomView = TRUE, zoomSpeed = 0.25,
    dragView = TRUE, hover = TRUE, tooltipDelay = 80
  ) %>%
  htmlwidgets::onRender(js_code)

tryCatch({
  message("Building circular-layout HTML...")
  saveWidget(vis_html_circle,
             normalizePath(file.path(out_dir, "dna_interactive_circle.html"), mustWork = FALSE),
             selfcontained = TRUE)
  message("Saved: dna_interactive_circle.html")
}, error = function(e) {
  message("ERROR generating circle HTML: ", conditionMessage(e))
})

# ----- 8. Summary tables (CSV) -----------------------------------------------

# Table 1: Count of positions per regulatory tool
table_position_by_tool <- df %>%
  count(regulatory_tool, position, name = "n_snippets") %>%
  arrange(regulatory_tool, desc(n_snippets))

write_csv(table_position_by_tool,
          file.path(out_dir, "table_position_by_tool.csv"))
message("Saved: table_position_by_tool.csv")

# Table 2: Count of positions per actor type
table_position_by_actor_type <- df %>%
  count(actor_type, position, name = "n_snippets") %>%
  arrange(actor_type, desc(n_snippets))

write_csv(table_position_by_actor_type,
          file.path(out_dir, "table_position_by_actor_type.csv"))
message("Saved: table_position_by_actor_type.csv")

# Table 3: Count of argument types per tool
table_argument_by_tool <- df %>%
  count(regulatory_tool, argument_type, name = "n_snippets") %>%
  arrange(regulatory_tool, desc(n_snippets))

write_csv(table_argument_by_tool,
          file.path(out_dir, "table_argument_by_tool.csv"))
message("Saved: table_argument_by_tool.csv")

# ----- 9. Console summary of key findings ------------------------------------
cat("\n")
cat("========================================================\n")
cat("  DISCOURSE NETWORK ANALYSIS — KEY FINDINGS\n")
cat("========================================================\n\n")

cat("--- Total coded snippets:", nrow(df), "\n\n")

cat("--- Positions by regulatory tool:\n")
print(as.data.frame(table_position_by_tool), row.names = FALSE)

cat("\n--- Positions by actor type:\n")
print(as.data.frame(table_position_by_actor_type), row.names = FALSE)

cat("\n--- Top argument types by tool:\n")
print(as.data.frame(table_argument_by_tool), row.names = FALSE)

if (nrow(congruence_edges) > 0) {
  top_coalition <- congruence_edges %>% arrange(desc(weight)) %>% slice(1)
  cat("\n--- Strongest coalition (most shared stances):\n")
  cat("  ", top_coalition$from, " <-> ", top_coalition$to,
      " (", top_coalition$weight, " shared tool(s): ", top_coalition$tools, ")\n", sep = "")
}

if (nrow(conflict_edges) > 0) {
  top_conflict <- conflict_edges %>% arrange(desc(weight)) %>% slice(1)
  cat("\n--- Strongest conflict (most opposed stances):\n")
  cat("  ", top_conflict$from, " <-> ", top_conflict$to,
      " (", top_conflict$weight, " tool(s): ", top_conflict$tools, ")\n", sep = "")
}

cat("\n--- Network density:\n")
if (nrow(congruence_edges) > 0) {
  cg <- graph_from_data_frame(congruence_edges, directed = FALSE)
  cat("  Congruence network density:", round(edge_density(cg), 3), "\n")
}
if (nrow(conflict_edges) > 0) {
  cf <- graph_from_data_frame(conflict_edges, directed = FALSE)
  cat("  Conflict network density:  ", round(edge_density(cf), 3), "\n")
}

cat("\n========================================================\n")
cat("Step 5 complete. Check outputs/step5/ for PNGs and HTML, outputs/step5_v2/ for improved PNGs.\n")
cat("========================================================\n")
