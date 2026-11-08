import type { LiveFile } from "./bridge";

/** What a live diff tab does with a newer state of its file. */
export type LiveFileUpdate =
  /** Rebuild with the new texts: the comparison or its editability changed. */
  | { kind: "reset" }
  /** Take the new texts in place, keeping cursor and scroll. */
  | { kind: "apply" }
  /** Unsaved edits stay; only the left side follows (a save will flag outside changes). */
  | { kind: "setBase" }
  /** Unsaved edits stay and the comparison changed under them; switch after they are saved. */
  | { kind: "keep" }
  /** The file has no changes left (discarded or committed elsewhere): close the tab. */
  | { kind: "close" };

export type LiveFileContext = {
  /** The tab holds unsaved edits. */
  dirty: boolean;
  /** Some earlier state of this tab had changes to show. */
  hadChanges: boolean;
  /** What this tab last saved, or null; a clean file the tab itself saved stays open. */
  savedContent: string | null;
};

export function planLiveFileUpdate(
  current: Pick<LiveFile, "view" | "editable">,
  next: LiveFile,
  context: LiveFileContext,
): LiveFileUpdate {
  if (next.view === "clean") {
    if (context.dirty) {
      return { kind: "setBase" };
    }
    // Changes discarded or committed somewhere else: like closing a file
    // whose diff has nothing left. One this tab saved back to the original
    // stays open, so the user can keep typing.
    if (context.hadChanges && context.savedContent !== next.content) {
      return { kind: "close" };
    }
    return current.editable === next.editable ? { kind: "apply" } : { kind: "reset" };
  }
  if (current.view !== next.view || current.editable !== next.editable) {
    return context.dirty ? { kind: "keep" } : { kind: "reset" };
  }
  return context.dirty ? { kind: "setBase" } : { kind: "apply" };
}
