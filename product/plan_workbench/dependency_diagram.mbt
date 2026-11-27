///|
// Only XML text and attributes are emitted. Authored data never becomes markup,
// an ID, a URL or a style. Reject characters that XML 1.0 cannot represent.
fn diagram_xml(value : String) -> String raise InputError {
  let out = StringBuilder()
  for c in value {
    let code = c.to_int()
    if (code < 32 && c != '\n' && c != '\r' && c != '\t') ||
      (code >= 0xD800 && code <= 0xDFFF) ||
      code == 0xFFFE ||
      code == 0xFFFF {
      raise Invalid(
        "Dependency map text contains a character unsupported by SVG/XML",
      )
    }
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&apos;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
// Conservative display-cell wrapping keeps Unicode scalars intact. No text is
// truncated; explicit authored line breaks are retained.
fn diagram_lines(value : String, width : Int32) -> Array[String] {
  let rows : Array[String] = []
  let normalized = value
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  for line in normalized.split("\n") {
    let mut text = StringBuilder()
    let mut count = 0
    for c in line {
      let cells = if c.to_int() > 127 { 2 } else { 1 }
      if count + cells > width {
        rows.push(text.to_string())
        text = StringBuilder()
        count = 0
      }
      text.write_char(c)
      count += cells
    }
    rows.push(text.to_string())
  }
  rows
}

///|
priv struct DiagramNode {
  task : Task
  x : Int32
  y : Int32
  height : Int32
  lines : Array[String]
  relation : String
  fill : String
}

///|
fn diagram_text(
  out : StringBuilder,
  x : Int32,
  y : Int32,
  text : String,
) -> Unit raise InputError {
  let text = diagram_xml(text)
  out.write_string(
    "<text x=\"\{x}\" y=\"\{y}\" xml:space=\"preserve\">\{text}</text>\n",
  )
}

///|
/// Export a standalone, deterministic SVG of current authored dependencies.
/// Waves express precedence, never elapsed time, capacity or completed work.
/// The selected task only highlights its relationship to the complete graph.
pub fn export_dependency_svg(
  draft : Draft,
  project_name : String,
  focus : String,
) -> String raise InputError {
  if draft.tasks.is_empty() || draft.tasks.length() > 100 {
    raise Invalid("Dependency map needs 1–100 planned tasks")
  }
  if draft.project_id.trim().is_empty() ||
    draft.key.trim().is_empty() ||
    project_name.trim().is_empty() {
    raise Invalid(
      "Dependency map needs a project identity, name and plan version",
    )
  }
  let graph = dependency_plan(draft, focus)
  guard graph.issues.is_empty() else { raise Invalid(graph.issues.join("\n")) }
  if !focus.is_empty() && !draft.tasks.any(t => t.id == focus) {
    raise Invalid("Selected task no longer exists; clear the diagram focus")
  }
  let mut edge_count = 0
  for task in draft.tasks {
    if task.id.trim().is_empty() {
      raise Invalid("Dependency map needs nonblank task IDs")
    }
    let seen : Array[String] = []
    for dep in task.dependencies {
      if seen.contains(dep) {
        raise Invalid(task.id + ": duplicate prerequisite " + dep)
      }
      seen.push(dep)
      edge_count += 1
    }
  }
  // This output is intended for inspectable project maps, not dense graph dumps.
  if edge_count > 500 {
    raise Invalid(
      "Dependency map supports at most 500 prerequisite links; export the text plan for a denser graph",
    )
  }
  let content_width = graph.waves.length() * 380 + 24
  let width = if content_width > 900 { content_width } else { 900 }
  let header = [
    ..diagram_lines(
      "Project: " + project_name + " [" + draft.project_id + "]",
      95,
    ),
    ..diagram_lines(
      "Plan version: " + draft.key + " | Revision: " + draft.prepared_at,
      95,
    ),
    "Planning only. Arrows: prerequisite -> dependent. Waves are precedence, not time.",
    "No task status, duration, owner capacity or authorization is inferred.",
    ..diagram_lines(
      if focus.is_empty() {
        "Focus: none; showing every task."
      } else {
        "Focus: " +
        focus +
        "; all tasks retained. Relationship labels do not rely on color."
      },
      95,
    ),
  ]
  let top = 70 + header.length() * 20
  let nodes : Array[DiagramNode] = []
  let mut bottom = top
  for wave_index, wave in graph.waves {
    let mut y = top + 32
    for id in wave {
      let task = draft.tasks.filter(t => t.id == id)[0]
      let owners = draft.owners.filter(o => o.id == task.owner)
      guard owners is [owner] else {
        raise Invalid(
          task.id + ": choose one existing owner before exporting a map",
        )
      }
      let milestones = draft.milestones.filter(m => m.id == task.milestone)
      guard milestones is [milestone] else {
        raise Invalid(
          task.id + ": choose one existing milestone before exporting a map",
        )
      }
      let (relation, fill) = if task.id == focus {
        ("FOCUS", "#fff1bf")
      } else if graph.prerequisites.contains(task.id) {
        ("PREREQUISITE OF FOCUS", "#e6f2ff")
      } else if graph.downstream.contains(task.id) {
        ("DOWNSTREAM OF FOCUS", "#efe7ff")
      } else {
        (
          if focus.is_empty() {
            "PLANNED TASK"
          } else {
            "OTHER PLANNED TASK"
          },
          "#f4f7fb",
        )
      }
      let lines = [
        ..diagram_lines("ID: " + task.id, 34),
        ..diagram_lines("Task: " + task.name, 34),
        ..diagram_lines("Owner: " + owner.name + " [" + owner.id + "]", 34),
        ..diagram_lines(
          "Milestone: " + milestone.name + " [" + milestone.id + "]",
          34,
        ),
        ..diagram_lines("Target (authored): " + milestone.date, 34),
      ]
      let height = 54 + lines.length() * 20
      nodes.push({
        task,
        x: 24 + wave_index * 380,
        y,
        height,
        lines,
        relation,
        fill,
      })
      y += height + 24
    }
    if y > bottom {
      bottom = y
    }
  }
  let edges = StringBuilder()
  let mut long_edges = 0
  for target in nodes {
    for dep in target.task.dependencies {
      let source = nodes.filter(n => n.task.id == dep)[0]
      let x1 = source.x + 320
      let y1 = source.y + source.height / 2
      let x2 = target.x
      let y2 = target.y + target.height / 2
      let path = if target.x - source.x == 380 {
        let mid = x1 + 30
        "M \{x1} \{y1} C \{mid} \{y1}, \{mid} \{y2}, \{x2} \{y2}"
      } else {
        // Long links route below the cards instead of passing through other tasks.
        let lane = bottom + 20 + long_edges * 18
        long_edges += 1
        let a = x1 + 16
        let b = x2 - 16
        "M \{x1} \{y1} H \{a} V \{lane} H \{b} V \{y2} H \{x2}"
      }
      let title = diagram_xml(dep + " -> " + target.task.id)
      edges.write_string(
        "<path class=\"dependency-edge\" d=\"\{path}\" fill=\"none\" stroke=\"#50627c\" stroke-width=\"1.5\" marker-end=\"url(#arrow)\"><title>\{title}</title></path>\n",
      )
    }
  }
  let height = bottom + 40 + long_edges * 18
  let out = StringBuilder()
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{width}\" height=\"\{height}\" viewBox=\"0 0 \{width} \{height}\" role=\"img\" aria-labelledby=\"map-title map-description\">\n",
  )
  out.write_string(
    "<title id=\"map-title\">" +
    diagram_xml("Dependency map: " + project_name) +
    "</title>\n",
  )
  out.write_string(
    "<desc id=\"map-description\">" +
    diagram_xml(
      dependency_report(draft, focus) +
      "\nPlan version: " +
      draft.key +
      "\nRevision: " +
      draft.prepared_at +
      "\nAuthored scope and source notes:\n" +
      draft.notes,
    ) +
    "</desc>\n",
  )
  out.write_string(
    "<defs><marker id=\"arrow\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"4\" orient=\"auto\"><path d=\"M 0 0 L 8 4 L 0 8 Z\" fill=\"#50627c\"/></marker></defs>\n",
  )
  out.write_string(
    "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n<g font-family=\"monospace\" font-size=\"14\" fill=\"#17253c\">\n",
  )
  out.write_string(
    "<text x=\"24\" y=\"32\" font-size=\"22\" font-weight=\"bold\">Project dependency map</text>\n",
  )
  for i, line in header {
    diagram_text(out, 24, 60 + i * 20, line)
  }
  for i, _ in graph.waves {
    diagram_text(out, 24 + i * 380, top + 12, "Wave " + (i + 1).to_string())
  }
  out.write_string(edges.to_string())
  for i, node in nodes {
    let x = node.x
    let y = node.y
    let h = node.height
    let fill = node.fill
    let description = diagram_xml(
      node.task.id +
      ": " +
      node.task.name +
      "\n" +
      node.relation +
      "\nPrerequisites: " +
      node.task.dependencies.join(", "),
    )
    out.write_string(
      "<g class=\"planned-task\" id=\"node-\{i}\" role=\"group\"><title>\{description}</title><rect x=\"\{x}\" y=\"\{y}\" width=\"320\" height=\"\{h}\" rx=\"8\" fill=\"\{fill}\" stroke=\"#50627c\"/>\n",
    )
    diagram_text(out, x + 14, y + 24, node.relation)
    for line_index, line in node.lines {
      diagram_text(out, x + 14, y + 50 + line_index * 20, line)
    }
    out.write_string("</g>\n")
  }
  out.write_string("</g>\n</svg>\n")
  out.to_string()
}
