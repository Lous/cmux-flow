/** What the native viewer actions talk to while a file is being edited. */
export type ActiveDiffEditor = {
  /** Handles a native viewer action; false when the editor does not own it. */
  performAction(action: string): boolean;
};

let activeEditor: ActiveDiffEditor | null = null;

/**
 * The page edits one file at a time; while it does, native viewer actions
 * (find, file and hunk navigation) belong to the editor, not the hidden diff.
 */
export function setActiveDiffEditor(editor: ActiveDiffEditor | null): void {
  activeEditor = editor;
}

export function activeDiffEditor(): ActiveDiffEditor | null {
  return activeEditor;
}
