#set page(paper: "a4")
#set text(font: "Linux Libertine", size: 11pt)

#align(center, text(17pt)[*My Typst Document*])

#grid(
  columns: (1fr, 1fr),
  align(center)[Researcher],
  align(center)[#datetime.today().display()],
)

= Introduction
This is a Typst document managed by tue-p8n/nix.
