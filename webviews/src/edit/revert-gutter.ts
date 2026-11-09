import { getChunks, rejectChunk } from "@codemirror/merge";
import type { EditorState, Extension } from "@codemirror/state";
import { type BlockInfo, type EditorView, gutter, GutterMarker, type ViewUpdate } from "@codemirror/view";

const svgNamespace = "http://www.w3.org/2000/svg";

/** A counter-clockwise arrow, like VS Code's revert icon. */
function revertIcon(): SVGSVGElement {
  const svg = document.createElementNS(svgNamespace, "svg");
  svg.setAttribute("viewBox", "0 0 16 16");
  svg.setAttribute("aria-hidden", "true");
  for (const d of ["M3.5 6.5h6.25a3.25 3.25 0 0 1 0 6.5H6.5", "M6.25 3.5 3.25 6.5l3 3"]) {
    const path = document.createElementNS(svgNamespace, "path");
    path.setAttribute("d", d);
    svg.appendChild(path);
  }
  return svg;
}

/** Sits on a change's first row; clicking it puts that change back to the comparison text. */
class RevertMarker extends GutterMarker {
  constructor(
    /** Where the change starts in the edited text, current for this marker's update. */
    readonly position: number,
    readonly label: string,
    readonly placeholder = false,
  ) {
    super();
  }

  override eq(other: GutterMarker): boolean {
    return other instanceof RevertMarker
      && other.position === this.position
      && other.label === this.label
      && other.placeholder === this.placeholder;
  }

  override toDOM(view: EditorView): Node {
    const element = document.createElement("div");
    element.className = "cmux-edit-revert-marker";
    element.appendChild(revertIcon());
    if (this.placeholder) {
      return element;
    }
    element.title = this.label;
    element.setAttribute("role", "button");
    element.setAttribute("aria-label", this.label);
    element.addEventListener("mousedown", (event) => {
      event.preventDefault();
      rejectChunk(view, this.position);
    });
    return element;
  }
}

function chunksOf(state: EditorState) {
  return getChunks(state)?.chunks ?? [];
}

/**
 * The unified diff's per-change revert, in the gutter the way VS Code shows it,
 * instead of `@codemirror/merge`'s buttons that float over the code. A change
 * with removed lines gets the icon beside them; one that only adds lines, beside
 * its first added line. Reverting is a normal edit, so Cmd+Z brings it back.
 */
export function revertGutter(label: string): Extension {
  return gutter({
    class: "cmux-edit-revert-gutter",
    lineMarker(view: EditorView, line: BlockInfo) {
      const chunk = chunksOf(view.state).find((candidate) => candidate.fromB === line.from);
      return chunk != null && chunk.fromA === chunk.toA ? new RevertMarker(chunk.fromB, label) : null;
    },
    widgetMarker(view: EditorView, _widget, block: BlockInfo) {
      const chunk = chunksOf(view.state).find((candidate) => candidate.fromB === block.from);
      return chunk != null && chunk.fromA < chunk.toA ? new RevertMarker(chunk.fromB, label) : null;
    },
    lineMarkerChange: (update: ViewUpdate) => getChunks(update.state)?.chunks !== getChunks(update.startState)?.chunks,
    // Keeps the gutter's width when the last change is reverted, so the code does not shift.
    initialSpacer: () => new RevertMarker(0, label, true),
  });
}
