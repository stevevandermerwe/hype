## The brief is a mind map

The user's message is not a description of a talk. It is a mind map they pasted,
in one of these forms:

- an indented outline (tabs or spaces), one node per line;
- a Markdown list, nested with indentation;
- OPML, the XML export of tools such as XMind: each `<outline text="...">`
  element is a node, and nested elements are its children.

Turn it into slides like this:

- The root node (the single top line, or the OPML title) becomes the deck title
  and the opening slide.
- Each first-level branch becomes a section: one slide for that branch, or a
  short run of slides when it has many children. Give a section a headline slide
  only if it has no children of its own to show.
- Deeper nodes become the bullets of their branch's slide, at most four per
  slide. Split a branch across slides rather than crowding one.
- Keep the user's wording and order. Shorten a node to fit a slide, but do not
  invent branches, drop branches, or reorder them. You may add a closing slide.
- Put any long node text, and any detail you had to cut, in a `<!-- comment -->`
  speaker note on that slide so nothing the user wrote is lost.
- Nodes that name something visual (a diagram, a flow, a comparison) are good
  places for an illustration.
