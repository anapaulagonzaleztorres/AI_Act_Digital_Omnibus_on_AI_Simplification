# =============================================================================
# Step 4: Network Visualization
# EU AI Act Omnibus Feedback — Actor-Position Bipartite Networks
#
# What this script does:
#   1. Loads the coded feedback data (80 rows)
#   2. Builds a bipartite network: actors on one side, positions on the other
#      An edge connects an actor to a position when they expressed that position
#   3. Saves 4 static PNG images (overall + one per regulatory tool)
#   4. Saves 1 interactive HTML file (hover to see actor details)
#
# How to run: Open in RStudio → click Source (top-right of script pane)
# =============================================================================

# ----- 0. Install packages if needed -----------------------------------------
required_pkgs <- c("tidyverse", "igraph", "ggraph", "visNetwork",
                   "htmlwidgets", "RColorBrewer", "ggrepel", "ggnewscale", "patchwork")
new_pkgs <- required_pkgs[!required_pkgs %in% installed.packages()[, "Package"]]
if (length(new_pkgs) > 0) {
  message("Installing missing packages: ", paste(new_pkgs, collapse = ", "))
  install.packages(new_pkgs, repos = "https://cloud.r-project.org")
}

library(tidyverse)
library(igraph)
library(ggraph)
library(visNetwork)
library(htmlwidgets)
library(RColorBrewer)
library(ggnewscale)
library(patchwork)

# ----- 1. Load & clean data --------------------------------------------------
script_dir <- tryCatch(
  dirname(rstudioapi::getSourceEditorContext()$path),
  error = function(e) "."   # repository copy: fall back to the working directory
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
out_dir    <- file.path(script_dir, "outputs", "step4")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

raw <- read_csv(data_path, show_col_types = FALSE)

# Keep only the columns we need and deduplicate on snippet_id
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

message("Rows after deduplication: ", nrow(df))

# ----- 2. Helper: build bipartite graph from a data frame --------------------
build_bipartite <- function(data) {
  actor_counts <- data %>%
    group_by(actor_name) %>%
    summarise(node_size = n(), .groups = "drop")

  position_counts <- data %>%
    group_by(position) %>%
    summarise(node_size = n_distinct(actor_name), .groups = "drop")

  actor_nodes <- data %>%
    distinct(actor_name, actor_type, country) %>%
    mutate(
      node_id   = paste0("A_", actor_name),
      node_type = "actor",
      label     = actor_name
    )
  actor_nodes <- actor_nodes %>% left_join(actor_counts, by = "actor_name")

  position_nodes <- data %>%
    distinct(position) %>%
    mutate(
      node_id   = paste0("P_", position),
      node_type = "position",
      label     = position
    )
  position_nodes <- position_nodes %>% left_join(position_counts, by = "position")

  nodes <- bind_rows(
    actor_nodes  %>% select(node_id, node_type, label, actor_type, country, node_size),
    position_nodes %>% select(node_id, node_type, label, node_size) %>%
      mutate(actor_type = NA, country = NA)
  )

  edges <- data %>%
    mutate(
      from = paste0("A_", actor_name),
      to   = paste0("P_", position)
    ) %>%
    select(from, to, argument_type)

  g <- graph_from_data_frame(edges, directed = FALSE, vertices = nodes)
  V(g)$type <- V(g)$node_type == "position"
  g
}

# ----- 3. Color palettes -----------------------------------------------------
# Colourblind-safe palette (Okabe & Ito 2008). Checked under simulated deuteranopia and
# protanopia; the closest pair is dE 10.0 apart. If you change a hex here, change it in
# the JS legend below too.
actor_type_colors <- c(
  "Business association"                          = "#0072B2",  # blue
  "Company/business"                              = "#E69F00",  # orange
  "Non-governmental organisation (NGO)"           = "#009E73",  # bluish green
  "Academic/research Institution"                 = "#CC79A7",  # reddish purple
  "Public authority"                              = "#D55E00",  # vermillion
  "Consumer organisation"                         = "#56B4E9",  # sky blue
  "Other"                                         = "#8C6D31"   # brown
)

# Blue family = pro, orange family = anti, grey = neutral. Deliberately shares no hex
# with actor_type_colors, so one colour never carries two meanings in one figure.
position_colors <- c(
  "pro_simplification"   = "#08519C",  # dark blue
  "pro_deregulation"     = "#6BAED6",  # mid blue
  "anti_simplification"  = "#A63603",  # dark orange-brown
  "anti_deregulation"    = "#FD8D3C",  # mid orange
  "neutral_ambivalent"   = "#969696"   # grey
)

POSITION_NODE_COLOR <- "#D4D4D4"

# ----- 4. Static plot function -----------------------------------------------
plot_network_static <- function(data, title, file_name) {
  if (nrow(data) == 0) {
    message("No data for: ", title, " — skipping")
    return(invisible(NULL))
  }

  g <- build_bipartite(data)

  node_df <- igraph::as_data_frame(g, what = "vertices")
  node_df$color_group <- ifelse(
    node_df$node_type == "actor",
    node_df$actor_type,
    node_df$label
  )
  node_df$color_group[is.na(node_df$color_group)] <- "Other"
  V(g)$color_group <- node_df$color_group

  pos_label_map <- c(
    "pro_simplification"  = "Pro-simplification",
    "pro_deregulation"    = "Pro-deregulation",
    "anti_simplification" = "Anti-simplification",
    "anti_deregulation"   = "Anti-deregulation",
    "neutral_ambivalent"  = "Neutral / ambivalent"
  )
  node_df$display_label <- ifelse(
    node_df$node_type == "position",
    pos_label_map[node_df$label],
    node_df$label
  )
  V(g)$display_label <- node_df$display_label

  p <- ggraph(g, layout = "bipartite") +
    geom_edge_link(alpha = 0.30, color = "#AAAAAA", width = 0.7) +
    # Scale 1 — Position squares
    geom_node_point(
      data = function(x) x[x$node_type == "position", ],
      aes(x = x, y = y, fill = color_group, size = node_size),
      shape = 22, color = "grey50", stroke = 0.4
    ) +
    {
      position_labels <- c(
        "pro_simplification"  = "Pro-simplification",
        "pro_deregulation"    = "Pro-deregulation",
        "anti_simplification" = "Anti-simplification",
        "anti_deregulation"   = "Anti-deregulation",
        "neutral_ambivalent"  = "Neutral / ambivalent"
      )
      present_positions <- intersect(names(position_colors), unique(data$position))
      scale_fill_manual(
        values = position_colors,
        breaks = present_positions,
        labels = position_labels[present_positions],
        name   = "Position Stance",
        guide  = guide_legend(
          override.aes = list(shape = 22, size = 4, color = "grey50", stroke = 0.4)
        )
      )
    } +
    new_scale_fill() +
    # Scale 2 — Actor circles
    geom_node_point(
      data = function(x) x[x$node_type == "actor", ],
      aes(x = x, y = y, fill = color_group, size = node_size),
      shape = 21, color = "white", stroke = 0.6
    ) +
    geom_node_label(
      data = function(x) x[x$node_type == "actor", ],
      aes(x = x, y = y, label = display_label),
      size = 4, color = "grey10", fill = "white", alpha = 0.85,
      label.size = 0.15, label.padding = unit(0.15, "lines"),
      repel = TRUE, max.overlaps = 50, family = "sans"
    ) +
    geom_node_label(
      data = function(x) x[x$node_type == "position", ],
      aes(x = x, y = y, label = display_label),
      size = 2.8, color = "grey10", fill = "white", alpha = 0.85,
      label.size = 0.15, label.padding = unit(0.15, "lines"),
      repel = TRUE, max.overlaps = 50, family = "sans"
    ) +
    {
      present_actor_types <- intersect(names(actor_type_colors), unique(data$actor_type))
      scale_fill_manual(
        values = actor_type_colors,
        breaks = present_actor_types,
        name   = "Actor Type",
        guide  = guide_legend(
          override.aes = list(shape = 21, size = 4, color = "grey40", stroke = 0.4)
        )
      )
    } +
    scale_size_area(max_size = 12, guide = "none") +
    labs(title    = title,
         subtitle = paste(nrow(data), "coded snippets")) +
    theme_graph(base_family = "sans") +
    theme(
      plot.title      = element_text(size = 13, face = "bold", color = "grey10"),
      plot.subtitle   = element_text(size = 10, color = "grey40"),
      legend.position = "right",
      legend.title    = element_text(face = "bold", size = 9),
      legend.text     = element_text(size = 8),
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin     = margin(10, 10, 20, 10)
    )

  out_path <- file.path(out_dir, file_name)
  ggsave(out_path, p, width = 22, height = 8, dpi = 150)
  message("Saved: ", out_path)
}

# ----- 5. Produce the 4 static PNGs ------------------------------------------
plot_network_static(df,
  title     = "Actor-Position Network — All Regulatory Tools",
  file_name = "network_overall.png")

plot_network_static(df %>% filter(regulatory_tool == "AI_standards"),
  title     = "Actor-Position Network — AI Standards",
  file_name = "network_AI_standards.png")

plot_network_static(df %>% filter(regulatory_tool == "GPAI_CoP"),
  title     = "Actor-Position Network — GPAI Code of Practice",
  file_name = "network_GPAI_CoP.png")

plot_network_static(df %>% filter(regulatory_tool == "AI_sandbox"),
  title     = "Actor-Position Network — AI Sandbox",
  file_name = "network_AI_sandbox.png")

# ----- 6. Interactive HTML with visNetwork -----------------------------------
build_vis_network <- function(data) {
  actor_counts <- data %>%
    group_by(actor_name) %>%
    summarise(n_snippets = n(), .groups = "drop")

  position_counts <- data %>%
    group_by(position) %>%
    summarise(n_actors = n_distinct(actor_name), .groups = "drop")

  # Nodes
  actor_nodes <- data %>%
    distinct(actor_name, actor_type, country) %>%
    mutate(
      id    = paste0("A_", actor_name),
      label = actor_name,
      group = actor_type,
      title = paste0("<b>", actor_name, "</b><br/>",
                     "Type: ", actor_type, "<br/>",
                     "Country: ", country),
      shape = "dot",
      color = actor_type_colors[actor_type]
    )
  actor_nodes$color[is.na(actor_nodes$color)] <- "#8C6D31"
  actor_nodes <- actor_nodes %>%
    left_join(actor_counts, by = "actor_name") %>%
    mutate(size = 10 + n_snippets * 2)

  position_nodes <- data %>%
    distinct(position) %>%
    left_join(position_counts, by = "position") %>%
    mutate(
      id    = paste0("P_", position),
      label = position,
      group = paste0("position_", position),
      title = paste0("<b>Position:</b> ", position),
      shape = "square",
      color = position_colors[position],
      size  = 10 + n_actors * 1.5
    )
  position_nodes$color[is.na(position_nodes$color)] <- "#BDBDBD"

  vis_nodes <- bind_rows(
    actor_nodes    %>% select(id, label, group, title, shape, color, size),
    position_nodes %>% select(id, label, group, title, shape, color, size)
  )

  vis_edges <- data %>%
    mutate(
      from  = paste0("A_", actor_name),
      to    = paste0("P_", position),
      title = paste0("Argument: ", argument_type,
                     "<br/>Tool: ", regulatory_tool)
    ) %>%
    select(from, to, title)

  visNetwork(vis_nodes, vis_edges,
             main    = list(text  = "EU AI Act Omnibus — Actor-Position Network",
                            style = "font-family:Arial,sans-serif; font-size:20px; font-weight:bold; color:#222;"),
             submain = list(text  = "Scroll to zoom &nbsp;·&nbsp; Drag background to pan &nbsp;·&nbsp; Hover nodes for details",
                            style = "font-family:Arial,sans-serif; font-size:12px; color:#888;"),
             width = "100%", height = "94vh") %>%
    visOptions(
      highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE),
      nodesIdSelection = list(enabled = FALSE)
    ) %>%
    visPhysics(
      solver = "forceAtlas2Based",
      forceAtlas2Based = list(gravitationalConstant = -120, springLength = 220,
                              springConstant = 0.05, damping = 0.9),
      stabilization    = list(enabled = TRUE, iterations = 300)
    ) %>%
    visNodes(font = list(size = 13, face = "Arial", color = "#333333"),
             shadow = list(enabled = TRUE, size = 4)) %>%
    visEdges(color  = list(color = "#CCCCCC", highlight = "#888888"),
             smooth = list(type = "continuous"), width = 1.2) %>%
    visInteraction(
      navigationButtons = TRUE,
      zoomView          = TRUE,
      zoomSpeed         = 0.25,
      dragView          = TRUE,
      hover             = TRUE,
      tooltipDelay      = 80
    ) %>%
    htmlwidgets::onRender("
      function(el, x) {
        setTimeout(function() {
         // ── 1. CUSTOM ACTOR-TYPE FILTER — top-left ──────────────────────────────────
         var network = HTMLWidgets.getInstance(el).network;
        
         var originalColors = {};
         network.body.data.nodes.forEach(function(n) {
           originalColors[n.id] = n.color;
         });
        
         var filterMode = 'hide';

         function applyFilter(selectedType) {
           var updates = [];
           network.body.data.nodes.forEach(function(n) {
             if (n.group && n.group.indexOf('position_') === 0) return;
             if (selectedType === 'All') {
               updates.push({ id: n.id, color: originalColors[n.id], hidden: false
         });
             } else if (n.group === selectedType) {
               updates.push({ id: n.id, color: originalColors[n.id], hidden: false
         });
             } else {
               if (filterMode === 'dim') {
                 updates.push({ id: n.id,
                   color: { background: '#e0e0e0', border: '#cccccc',
                            highlight: { background: '#e0e0e0', border: '#cccccc' }
          },
                   hidden: false });
               } else {
                 updates.push({ id: n.id, hidden: true });
               }
             }
           });
           network.body.data.nodes.update(updates);
         }
        
         var filterPanel = document.createElement('div');
         filterPanel.style.cssText =
           'position:absolute;top:100px;left:40px;z-index:20;' +
           'background:rgba(255,255,255,0.96);padding:10px 14px;' +
           'border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.13);' +
           'font-family:Arial,sans-serif;min-width:190px;';
        
         var lbl = document.createElement('div');
         lbl.textContent = 'Filter by actor type:';
         lbl.style.cssText =
           'font-size:11px;font-weight:bold;color:#555;text-transform:uppercase;' +
           'letter-spacing:0.05em;margin-bottom:6px;';
         filterPanel.appendChild(lbl);
        
         var sel = document.createElement('select');
         sel.style.cssText =
           'width:100%;padding:5px 8px;font-size:12px;border:1px solid #ccc;' +
           'border-radius:4px;font-family:Arial,sans-serif;cursor:pointer;margin-bottom:8px;';
         var actorTypes = [
           'All actor types',
           'Business association',
           'Company/business',
           'Non-governmental organisation (NGO)',
           'Academic/research Institution',
           'Public authority',
           'Consumer organisation',
           'Other'
         ];
         actorTypes.forEach(function(t) {
           var opt = document.createElement('option');
           opt.value = (t === 'All actor types') ? 'All' : t;
           opt.textContent = t;
           sel.appendChild(opt);
         });
         sel.addEventListener('change', function() { applyFilter(this.value); });
         filterPanel.appendChild(sel);
        
         var modeLbl = document.createElement('div');
         modeLbl.textContent = 'Others:';
         modeLbl.style.cssText =
           'font-size:11px;font-weight:bold;color:#555;text-transform:uppercase;' +
           'letter-spacing:0.05em;margin-bottom:5px;';
         filterPanel.appendChild(modeLbl);
        
         var btnRow = document.createElement('div');
         btnRow.style.cssText = 'display:flex;gap:6px;';
        
         function makeToggleBtn(text, isActive) {
           var btn = document.createElement('button');
           btn.textContent = text;
           btn.style.cssText =
             'flex:1;padding:4px 0;font-size:11px;border-radius:4px;cursor:pointer;' +
             'font-family:Arial,sans-serif;border:1px solid #ccc;';
           btn.style.background = isActive ? '#4E79A7' : 'white';
           btn.style.color      = isActive ? 'white'   : '#333';
           return btn;
         }
        
         var btnDim  = makeToggleBtn('Dim',  false);
         var btnHide = makeToggleBtn('Hide', true);
        
         btnDim.addEventListener('click', function() {
           filterMode = 'dim';
           btnDim.style.background  = '#4E79A7'; btnDim.style.color  = 'white';
           btnHide.style.background = 'white';   btnHide.style.color = '#333';
           applyFilter(sel.value);
         });
         btnHide.addEventListener('click', function() {
           filterMode = 'hide';
           btnHide.style.background = '#4E79A7'; btnHide.style.color = 'white';
           btnDim.style.background  = 'white';   btnDim.style.color  = '#333';
           applyFilter(sel.value);
         });
        
         btnRow.appendChild(btnDim);
         btnRow.appendChild(btnHide);
         filterPanel.appendChild(btnRow);
         el.appendChild(filterPanel);

         // ── Node-click: hide non-connected nodes ────────────────────────────────────
         var clickedNodeId = null;
         network.on('click', function(params) {
           if (params.nodes.length > 0) {
             clickedNodeId = params.nodes[0];
             var connected = network.getConnectedNodes(clickedNodeId);
             connected.push(clickedNodeId);
             var updates = [];
             network.body.data.nodes.forEach(function(n) {
               if (n.group && n.group.indexOf('position_') === 0) return;
               updates.push({ id: n.id, hidden: connected.indexOf(n.id) === -1 });
             });
             network.body.data.nodes.update(updates);
           } else if (clickedNodeId !== null) {
             clickedNodeId = null;
             applyFilter(sel.value);   // restore dropdown filter state
           }
         });
         // ── END node-click ───────────────────────────────────────────────────────────

         // ── END CUSTOM FILTER ────────────────────────────────────────────────────────

          // ── 2. NAV BUTTONS — below the dropdown ──
          var nav = el.querySelector('.vis-navigation');
          if (nav) {
            nav.style.position     = 'absolute';
            nav.style.top          = '170px';
            nav.style.left         = '14px';
            nav.style.right        = 'auto';
            nav.style.bottom       = 'auto';
            nav.style.width        = '120px';
            nav.style.height       = '120px';
            nav.style.background   = 'rgba(255,255,255,0.93)';
            nav.style.borderRadius = '8px';
            nav.style.boxShadow    = '0 2px 6px rgba(0,0,0,0.15)';
            nav.style.zIndex       = '10';

            var layout = {
              'vis-up':          { top:  5, left: 43 },
              'vis-left':        { top: 43, left:  5 },
              'vis-down':        { top: 43, left: 43 },
              'vis-right':       { top: 43, left: 81 },
              'vis-zoomIn':      { top: 81, left:  5 },
              'vis-zoomOut':     { top: 81, left: 43 },
              'vis-zoomExtends': { top: 81, left: 81 }
            };
            Object.keys(layout).forEach(function(cls) {
              var btn = nav.querySelector('.' + cls);
              if (!btn) return;
              btn.style.position        = 'absolute';
              btn.style.top             = layout[cls].top  + 'px';
              btn.style.left            = layout[cls].left + 'px';
              btn.style.right           = 'auto';
              btn.style.bottom          = 'auto';
              btn.style.width           = '30px';
              btn.style.height          = '30px';
              btn.style.borderRadius    = '50%';
              btn.style.cursor          = 'pointer';
              btn.style.backgroundColor = '#e8f5e9';
              btn.style.border          = '1px solid #a5d6a7';
            });
          }

          // ── 3. LEGEND PANEL — top-right ──
          // Must stay in sync with actor_type_colors / position_colors in the R above.
          var actors = [
            { label: 'Business association',                color: '#0072B2' },
            { label: 'Company/business',                    color: '#E69F00' },
            { label: 'Non-governmental organisation (NGO)', color: '#009E73' },
            { label: 'Academic/research Institution',       color: '#CC79A7' },
            { label: 'Public authority',                    color: '#D55E00' },
            { label: 'Consumer organisation',               color: '#56B4E9' },
            { label: 'Other',                               color: '#8C6D31' }
          ];
          var positions = [
            { label: 'Pro-simplification',   color: '#08519C' },
            { label: 'Pro-deregulation',     color: '#6BAED6' },
            { label: 'Anti-simplification',  color: '#A63603' },
            { label: 'Anti-deregulation',    color: '#FD8D3C' },
            { label: 'Neutral / ambivalent', color: '#969696' }
          ];

          function legendRow(color, shape, label) {
            var dot = shape === 'circle'
              ? 'width:13px;height:13px;border-radius:50%;background:' + color
              : 'width:13px;height:13px;border-radius:2px;background:' + color;
            return '<div style=\"display:flex;align-items:center;margin-bottom:5px;\">' +
              '<span style=\"' + dot + ';flex-shrink:0;margin-right:8px;display:inline-block;\"></span>' +
              '<span style=\"font-size:12px;color:#333;font-family:Arial,sans-serif;\">' + label + '</span></div>';
          }

          function legendHeader(text) {
            return '<div style=\"font-size:11px;font-weight:bold;letter-spacing:0.06em;' +
              'color:#555;font-family:Arial,sans-serif;text-transform:uppercase;' +
              'margin-bottom:8px;border-bottom:1px solid #e0e0e0;padding-bottom:4px;\">' + text + '</div>';
          }

          var legendHTML =
            legendHeader('Actor Type') +
            actors.map(function(a) { return legendRow(a.color, 'circle', a.label); }).join('') +
            '<div style=\"margin-top:12px;\"></div>' +
            legendHeader('Position Stance') +
            positions.map(function(p) { return legendRow(p.color, 'square', p.label); }).join('');

          var old = el.querySelector('.vis-legend');
          if (old) old.style.display = 'none';

          var panel = document.createElement('div');
          panel.style.cssText = 'position:absolute;top:14px;right:14px;' +
            'background:rgba(255,255,255,0.96);padding:14px 18px;' +
            'border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.13);' +
            'z-index:10;min-width:235px;';
          panel.innerHTML = legendHTML;
          el.appendChild(panel);

        }, 950);
      }
    ")
}

vis_html <- build_vis_network(df)
html_path <- file.path(out_dir, "network_interactive.html")
saveWidget(vis_html, html_path, selfcontained = TRUE)
message("Saved interactive HTML: ", html_path)

message("\nStep 4 complete. Check the outputs/step4/ folder for 4 PNG files and 1 HTML file.")

# =============================================================================
# STEP 4B — Aggregated static views: grouped by ACTOR TYPE instead of
# individual organisation. This declutters the picture (7 actor types + 5
# positions instead of 50+ named organisations) while keeping the same
# colour palettes as the original plots. Saved as new files — none of the
# original 4 PNGs above are modified or overwritten.
# =============================================================================

# ----- 7. Helper: build a small bipartite graph of actor_type <-> position ---
build_bipartite_by_type <- function(data) {
  edge_df <- data %>%
    group_by(actor_type, position) %>%
    summarise(weight = n(), n_actors = n_distinct(actor_name), .groups = "drop")

  type_nodes <- data %>%
    group_by(actor_type) %>%
    summarise(node_size = n(), .groups = "drop") %>%
    mutate(node_id = paste0("T_", actor_type), node_type = "actor_type", label = actor_type)

  position_nodes <- data %>%
    group_by(position) %>%
    summarise(node_size = n_distinct(actor_name), .groups = "drop") %>%
    mutate(node_id = paste0("P_", position), node_type = "position", label = position)

  nodes <- bind_rows(
    type_nodes     %>% select(node_id, node_type, label, node_size),
    position_nodes %>% select(node_id, node_type, label, node_size)
  )

  edges <- edge_df %>%
    mutate(from = paste0("T_", actor_type), to = paste0("P_", position)) %>%
    select(from, to, weight, n_actors)

  g <- graph_from_data_frame(edges, directed = FALSE, vertices = nodes)
  V(g)$type <- V(g)$node_type == "position"
  g
}

# ----- 8. Plot function: actor type vs. position, edge width = strength -----
plot_network_by_actor_type <- function(data, title, file_name = NULL, save = TRUE) {
  if (nrow(data) == 0) {
    message("No data for: ", title, " — skipping")
    return(invisible(NULL))
  }

  g <- build_bipartite_by_type(data)

  node_df <- igraph::as_data_frame(g, what = "vertices")
  V(g)$color_group <- node_df$label

  pos_label_map <- c(
    "pro_simplification"  = "Pro-simplification",
    "pro_deregulation"    = "Pro-deregulation",
    "anti_simplification" = "Anti-simplification",
    "anti_deregulation"   = "Anti-deregulation",
    "neutral_ambivalent"  = "Neutral / ambivalent"
  )
  node_df$display_label <- ifelse(
    node_df$node_type == "position",
    pos_label_map[node_df$label],
    node_df$label
  )
  V(g)$display_label <- node_df$display_label

  present_positions   <- intersect(names(position_colors), unique(data$position))
  present_actor_types <- intersect(names(actor_type_colors), unique(data$actor_type))

  p <- ggraph(g, layout = "bipartite") +
    geom_edge_link(aes(width = weight), alpha = 0.45, color = "#888888", lineend = "round") +
    scale_edge_width(range = c(0.6, 8), name = "Snippets", guide = "none") +
    # Scale 1 — Position squares
    geom_node_point(
      data = function(x) x[x$node_type == "position", ],
      aes(x = x, y = y, fill = color_group, size = node_size),
      shape = 22, color = "grey50", stroke = 0.4
    ) +
    scale_fill_manual(
      values = position_colors,
      breaks = present_positions,
      labels = pos_label_map[present_positions],
      name   = "Position Stance",
      guide  = guide_legend(override.aes = list(shape = 22, size = 4, color = "grey50", stroke = 0.4))
    ) +
    new_scale_fill() +
    # Scale 2 — Actor-type circles
    geom_node_point(
      data = function(x) x[x$node_type == "actor_type", ],
      aes(x = x, y = y, fill = color_group, size = node_size),
      shape = 21, color = "white", stroke = 0.6
    ) +
    scale_fill_manual(
      values = actor_type_colors,
      breaks = present_actor_types,
      name   = "Actor Type",
      guide  = guide_legend(override.aes = list(shape = 21, size = 4, color = "grey40", stroke = 0.4))
    ) +
    geom_node_label(
      data = function(x) x[x$node_type == "actor_type", ],
      aes(x = x, y = y, label = display_label),
      size = 3.6, color = "grey10", fill = "white", alpha = 0.9,
      label.size = 0.15, label.padding = unit(0.18, "lines"),
      repel = TRUE, max.overlaps = 20, family = "sans"
    ) +
    geom_node_label(
      data = function(x) x[x$node_type == "position", ],
      aes(x = x, y = y, label = display_label),
      size = 3.0, color = "grey10", fill = "white", alpha = 0.9,
      label.size = 0.15, label.padding = unit(0.18, "lines"),
      repel = TRUE, max.overlaps = 20, family = "sans"
    ) +
    scale_size_area(max_size = 24, guide = "none") +
    labs(title = title, subtitle = paste(nrow(data), "coded snippets, grouped by actor type")) +
    theme_graph(base_family = "sans") +
    theme(
      plot.title      = element_text(size = 13, face = "bold", color = "grey10"),
      plot.subtitle   = element_text(size = 10, color = "grey40"),
      legend.position = "right",
      legend.title    = element_text(face = "bold", size = 9),
      legend.text     = element_text(size = 8),
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin     = margin(10, 10, 20, 10)
    )

  if (save && !is.null(file_name)) {
    out_path <- file.path(out_dir, file_name)
    ggsave(out_path, p, width = 12, height = 8, dpi = 150)
    message("Saved: ", out_path)
  }

  invisible(p)
}

# ----- 9. Produce the 4 aggregated PNGs (mirrors the original 4 above) ------
plot_network_by_actor_type(df,
  title     = "Actor Type vs. Position — All Regulatory Tools",
  file_name = "network_overall_by_actor_type.png")

plot_network_by_actor_type(df %>% filter(regulatory_tool == "AI_standards"),
  title     = "Actor Type vs. Position — AI Standards",
  file_name = "network_AI_standards_by_actor_type.png")

plot_network_by_actor_type(df %>% filter(regulatory_tool == "GPAI_CoP"),
  title     = "Actor Type vs. Position — GPAI Code of Practice",
  file_name = "network_GPAI_CoP_by_actor_type.png")

plot_network_by_actor_type(df %>% filter(regulatory_tool == "AI_sandbox"),
  title     = "Actor Type vs. Position — AI Sandbox",
  file_name = "network_AI_sandbox_by_actor_type.png")

# ----- 10. Side-by-side 3-panel comparison across regulatory tools ----------
# Puts AI Standards / GPAI CoP / AI Sandbox next to each other so the
# difference in stakeholder agreement (Step 6 finding) is visible at a glance.
plot_standards <- plot_network_by_actor_type(
  df %>% filter(regulatory_tool == "AI_standards"), title = "AI Standards", save = FALSE)
plot_gpai <- plot_network_by_actor_type(
  df %>% filter(regulatory_tool == "GPAI_CoP"), title = "GPAI Code of Practice", save = FALSE)
plot_sandbox <- plot_network_by_actor_type(
  df %>% filter(regulatory_tool == "AI_sandbox"), title = "AI Sandbox", save = FALSE)

comparison_plot <- (plot_standards | plot_gpai | plot_sandbox) +
  plot_layout(guides = "collect") +
  plot_annotation(
    title = "Actor Type vs. Position, by Regulatory Tool",
    theme = theme(plot.title = element_text(size = 15, face = "bold", hjust = 0.5))
  ) &
  theme(legend.position = "bottom")

comparison_path <- file.path(out_dir, "network_tools_comparison_by_actor_type.png")
ggsave(comparison_path, comparison_plot, width = 24, height = 9, dpi = 150)
message("Saved: ", comparison_path)

message("\nStep 4B complete. 5 new 'by actor type' PNGs saved to outputs/step4/ (originals untouched).")
