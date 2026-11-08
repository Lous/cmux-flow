// Loaded on demand (dynamic import) the first time a file is edited, so the
// diff viewer's eager bundle never evaluates CodeMirror.
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import {
  bracketMatching,
  HighlightStyle,
  indentOnInput,
  indentUnit,
  LanguageDescription,
  syntaxHighlighting,
} from "@codemirror/language";
import { languages } from "@codemirror/language-data";
import {
  getChunks,
  getOriginalDoc,
  goToNextChunk,
  goToPreviousChunk,
  MergeView,
  originalDocChangeEffect,
  unifiedMergeView,
} from "@codemirror/merge";
import {
  closeSearchPanel,
  findNext,
  findPrevious,
  highlightSelectionMatches,
  openSearchPanel,
  search,
  searchKeymap,
  searchPanelOpen,
} from "@codemirror/search";
import { ChangeSet, Compartment, EditorSelection, EditorState, type Extension, Text, Transaction } from "@codemirror/state";
import {
  crosshairCursor,
  drawSelection,
  dropCursor,
  EditorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  highlightSpecialChars,
  keymap,
  lineNumbers,
  rectangularSelection,
} from "@codemirror/view";
import { tags } from "@lezer/highlight";

export type DiffEditorLayout = "split" | "unified";

export type DiffEditorLabels = {
  revertChange: string;
};

export type DiffEditorOptions = {
  parent: HTMLElement;
  path: string;
  /** The right side: the file being edited (or read). */
  content: string;
  /** The left side, always read-only. */
  base: string;
  /** False shows the right side read-only too (staged text, deleted files). */
  editable: boolean;
  layout: DiffEditorLayout;
  wordWrap: boolean;
  labels: DiffEditorLabels;
  /** Called when the editor's text starts or stops matching what was last saved. */
  onDirtyChange: (dirty: boolean) => void;
  /** Cmd+S. */
  onSave: () => void;
};

export type DiffEditorHandle = {
  /** The right side's text, with the file's own line endings. */
  getContent(): string;
  isDirty(): boolean;
  /** Records `content` as what is on disk, for dirty tracking. */
  markSaved(content: string): void;
  /**
   * Takes a newer disk/index state while the user has nothing unsaved: the
   * texts change by their smallest difference, so the cursor, selection and
   * scroll stay where they were. Not undoable, like a reload in VS Code.
   */
  applyExternal(content: string, base: string): void;
  /** Takes a newer comparison text, keeping unsaved edits on the right side. */
  setBase(base: string): void;
  /** Rebuilds both sides (another comparison, or editability changed). */
  reset(content: string, base: string, editable: boolean): void;
  setLayout(layout: DiffEditorLayout): void;
  setWordWrap(wordWrap: boolean): void;
  focus(): void;
  /** Handles a native viewer action (find); false when not the editor's. */
  performAction(action: string): boolean;
  destroy(): void;
};

/** The smallest single replacement turning `from` into `to`, in `\n`-joined text. */
function smallestChange(from: string, to: string): { from: number; to: number; insert: string } | null {
  if (from === to) return null;
  const max = Math.min(from.length, to.length);
  let start = 0;
  while (start < max && from.charCodeAt(start) === to.charCodeAt(start)) start += 1;
  let endFrom = from.length;
  let endTo = to.length;
  while (endFrom > start && endTo > start && from.charCodeAt(endFrom - 1) === to.charCodeAt(endTo - 1)) {
    endFrom -= 1;
    endTo -= 1;
  }
  return { from: start, to: endFrom, insert: to.slice(start, endTo) };
}

const token = (role: string) => `var(--cmux-edit-${role})`;

/** Mirrors the terminal theme's TextMate scopes (see `editor-palette.ts`). */
const terminalHighlightStyle = HighlightStyle.define([
  { tag: [tags.comment, tags.lineComment, tags.blockComment, tags.docComment], color: token("comment"), fontStyle: "italic" },
  { tag: [tags.string, tags.special(tags.string), tags.character, tags.regexp, tags.attributeValue], color: token("string") },
  { tag: [tags.number, tags.integer, tags.float, tags.bool, tags.null, tags.atom, tags.constant(tags.name)], color: token("constant") },
  {
    tag: [
      tags.keyword,
      tags.controlKeyword,
      tags.definitionKeyword,
      tags.moduleKeyword,
      tags.operatorKeyword,
      tags.modifier,
      tags.self,
      tags.operator,
    ],
    color: token("keyword"),
  },
  {
    tag: [
      tags.function(tags.variableName),
      tags.function(tags.definition(tags.variableName)),
      tags.function(tags.propertyName),
      tags.macroName,
    ],
    color: token("function"),
  },
  { tag: [tags.typeName, tags.className, tags.namespace, tags.definition(tags.typeName)], color: token("type") },
  { tag: tags.heading, color: token("heading"), fontWeight: "bold" },
  { tag: tags.strong, color: token("bold"), fontWeight: "bold" },
  { tag: tags.emphasis, color: token("italic"), fontStyle: "italic" },
  { tag: tags.monospace, color: token("raw") },
  { tag: [tags.link, tags.url], color: token("link") },
  { tag: tags.quote, color: token("quote"), fontStyle: "italic" },
  { tag: tags.list, color: token("list") },
  { tag: tags.invalid, color: token("invalid") },
]);

const editorTheme = EditorView.theme({
  "&": {
    height: "100%",
    color: token("fg"),
    backgroundColor: "transparent",
    fontSize: "var(--cmux-diff-font-size)",
  },
  ".cm-scroller": {
    fontFamily: "var(--cmux-diff-code-font-family)",
    lineHeight: "var(--cmux-diff-line-height)",
    overflow: "auto",
  },
  ".cm-content": { caretColor: token("fg") },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: token("fg") },
  // Gutters stay pinned while long lines scroll sideways; an opaque fill keeps
  // the scrolled code from showing through the line numbers.
  ".cm-gutters": {
    backgroundColor: "var(--cmux-diff-bg)",
    color: "var(--cmux-diff-text-muted)",
    border: "none",
  },
  ".cm-activeLine": { backgroundColor: "var(--cmux-diff-muted-bg)" },
  ".cm-activeLineGutter": { backgroundColor: "var(--cmux-diff-muted-bg)" },
  "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    backgroundColor: "light-dark(var(--cmux-diff-selection-bg-light), var(--cmux-diff-selection-bg-dark))",
  },
  ".cm-panels": {
    backgroundColor: "var(--cmux-diff-bg)",
    color: "var(--cmux-diff-fg)",
    fontFamily: "var(--cmux-diff-ui-font-family)",
  },
  ".cm-panels.cm-panels-top": { borderBottom: "1px solid var(--cmux-diff-border)" },
});

function languageFor(path: string): LanguageDescription | null {
  return LanguageDescription.matchFilename(languages, path.split("/").pop() ?? path);
}

/** `\r\n` when most line breaks are CRLF, so saving keeps the file's line endings. */
function lineSeparatorOf(text: string): string | undefined {
  const crlf = text.match(/\r\n/g)?.length ?? 0;
  const lf = (text.match(/\n/g)?.length ?? 0) - crlf;
  return crlf > lf ? "\r\n" : undefined;
}

/** Tabs when lines are tab-indented, else the most common space indent (2 or 4). */
function indentOf(text: string): string {
  let tabs = 0;
  let twos = 0;
  let fours = 0;
  for (const line of text.split("\n", 2000)) {
    if (line.startsWith("\t")) tabs += 1;
    const spaces = line.match(/^ +/)?.[0].length ?? 0;
    if (spaces === 0) continue;
    if (spaces % 4 === 0) fours += 1;
    else if (spaces % 2 === 0) twos += 1;
  }
  if (tabs > twos + fours) return "\t";
  return twos >= fours / 2 && twos > 0 ? "  " : fours > 0 ? "    " : "  ";
}

function revertOnlyControl(label: string) {
  return (type: "reject" | "accept", action: (event: MouseEvent) => void): HTMLElement => {
    const button = document.createElement("button");
    if (type === "accept") {
      // Accepting would only rewrite the in-memory comparison text; editing
      // the file is the accept. Keep the slot, never show it.
      button.hidden = true;
      return button;
    }
    button.type = "button";
    button.name = "reject";
    button.className = "cmux-edit-revert";
    button.textContent = label;
    button.title = label;
    button.onmousedown = action;
    return button;
  };
}

export function createDiffEditor(options: DiffEditorOptions): DiffEditorHandle {
  const languageCompartment = new Compartment();
  const wrapCompartment = new Compartment();
  let loadedLanguage: Extension = [];
  // What is on disk, split into lines the way the editor's state splits them.
  let savedDoc = Text.empty;
  let dirty = false;
  let baseText = options.base;
  let editable = options.editable;
  let wordWrap = options.wordWrap;
  let layout = options.layout;
  let merge: MergeView | null = null;
  let unified: EditorView | null = null;

  const editableView = (): EditorView => (merge ? merge.b : unified!);
  const views = (): EditorView[] => (merge ? [merge.a, merge.b] : unified ? [unified] : []);

  const setDirty = (next: boolean) => {
    if (next !== dirty) {
      dirty = next;
      options.onDirtyChange(dirty);
    }
  };

  const sharedExtensions = (text: string): Extension[] => {
    const separator = lineSeparatorOf(text);
    return [
      lineNumbers(),
      highlightSpecialChars(),
      drawSelection(),
      syntaxHighlighting(terminalHighlightStyle),
      bracketMatching(),
      highlightSelectionMatches(),
      search({ top: true }),
      keymap.of(searchKeymap),
      editorTheme,
      languageCompartment.of(loadedLanguage),
      wrapCompartment.of(wordWrap ? EditorView.lineWrapping : []),
      separator ? EditorState.lineSeparator.of(separator) : [],
    ];
  };

  // Read-only sides still take a cursor and selection, so text can be copied.
  const readOnlyExtensions = (text: string): Extension[] => [
    ...sharedExtensions(text),
    EditorState.readOnly.of(true),
  ];

  const rightSideExtensions = (text: string): Extension[] => {
    if (!editable) {
      return [
        ...readOnlyExtensions(text),
        highlightActiveLineGutter(),
        keymap.of([
          { key: "F7", run: goToNextChunk },
          { key: "Shift-F7", run: goToPreviousChunk },
          ...defaultKeymap,
        ]),
      ];
    }
    return [
      ...sharedExtensions(text),
      history(),
      dropCursor(),
      rectangularSelection(),
      crosshairCursor(),
      highlightActiveLine(),
      highlightActiveLineGutter(),
      indentOnInput(),
      closeBrackets(),
      indentUnit.of(indentOf(text)),
      EditorState.allowMultipleSelections.of(true),
      keymap.of([
        { key: "Mod-s", preventDefault: true, run: () => { options.onSave(); return true; } },
        { key: "F7", run: goToNextChunk },
        { key: "Shift-F7", run: goToPreviousChunk },
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...historyKeymap,
        indentWithTab,
      ]),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          setDirty(!update.state.doc.eq(savedDoc));
        }
      }),
    ];
  };

  const teardown = () => {
    // MergeView.destroy() also destroys both of its editors.
    merge?.destroy();
    unified?.destroy();
    merge = null;
    unified = null;
    options.parent.replaceChildren();
  };

  const build = (content: string, base: string, selection?: EditorSelection) => {
    teardown();
    if (layout === "split") {
      merge = new MergeView({
        a: { doc: base, extensions: readOnlyExtensions(base) },
        b: { doc: content, selection, extensions: rightSideExtensions(content) },
        parent: options.parent,
        revertControls: editable ? "a-to-b" : undefined,
        gutter: true,
        highlightChanges: true,
      });
    } else {
      unified = new EditorView({
        state: EditorState.create({
          doc: content,
          selection,
          extensions: [
            ...rightSideExtensions(content),
            unifiedMergeView({
              original: base,
              gutter: true,
              highlightChanges: true,
              syntaxHighlightDeletions: true,
              mergeControls: editable ? revertOnlyControl(options.labels.revertChange) : false,
            }),
          ],
        }),
        parent: options.parent,
      });
    }
    savedDoc = editableView().state.doc;
  };

  const currentBase = (): string => (merge ? merge.a.state.sliceDoc() : baseText);

  /** Puts the cursor on the first change and scrolls it to the middle, the way a diff reads. */
  const revealFirstChange = () => {
    // `build` assigns `merge` inside a closure, which narrowing cannot see.
    const builtMerge = merge as MergeView | null;
    const firstChange = builtMerge ? builtMerge.chunks[0]?.fromB : getChunks(editableView().state)?.chunks[0]?.fromB;
    if (firstChange == null) return;
    const view = editableView();
    const line = view.state.doc.lineAt(Math.min(firstChange, view.state.doc.length));
    view.dispatch({
      selection: EditorSelection.cursor(line.from),
      effects: EditorView.scrollIntoView(line.from, { y: "center" }),
    });
  };

  /** Moves `view`'s text to `text` by its smallest change, outside undo history. */
  const replaceText = (view: EditorView, text: string) => {
    const target = view.state.toText(text);
    const change = smallestChange(view.state.doc.toString(), target.toString());
    if (change == null) return;
    view.dispatch({
      changes: { from: change.from, to: change.to, insert: Text.of(change.insert.split("\n")) },
      annotations: Transaction.addToHistory.of(false),
    });
  };

  const replaceBase = (base: string) => {
    baseText = base;
    if (merge) {
      replaceText(merge.a, base);
      return;
    }
    const view = editableView();
    const original = getOriginalDoc(view.state);
    const target = view.state.toText(base);
    const change = smallestChange(original.toString(), target.toString());
    if (change == null) return;
    const changes = ChangeSet.of(
      [{ from: change.from, to: change.to, insert: Text.of(change.insert.split("\n")) }],
      original.length,
    );
    view.dispatch({ effects: originalDocChangeEffect(view.state, changes) });
  };

  build(options.content, options.base);
  revealFirstChange();

  const description = languageFor(options.path);
  if (description) {
    void description.load().then((support) => {
      loadedLanguage = support;
      for (const view of views()) {
        view.dispatch({ effects: languageCompartment.reconfigure(support) });
      }
    }).catch(() => {});
  }

  return {
    getContent: () => editableView().state.sliceDoc(),
    isDirty: () => dirty,
    markSaved(content: string) {
      savedDoc = editableView().state.toText(content);
      setDirty(!editableView().state.doc.eq(savedDoc));
    },
    applyExternal(content: string, base: string) {
      replaceBase(base);
      const view = editableView();
      replaceText(view, content);
      savedDoc = view.state.doc;
      setDirty(false);
    },
    setBase: replaceBase,
    reset(content: string, base: string, nextEditable: boolean) {
      baseText = base;
      editable = nextEditable;
      build(content, base);
      setDirty(false);
      revealFirstChange();
    },
    setLayout(next: DiffEditorLayout) {
      if (next === layout) return;
      const content = editableView().state.sliceDoc();
      const base = currentBase();
      const selection = editableView().state.selection;
      const saved = savedDoc;
      layout = next;
      // Undo history does not survive the rebuild; the text, cursor and
      // unsaved state do.
      build(content, base, selection);
      savedDoc = saved;
      setDirty(!editableView().state.doc.eq(savedDoc));
    },
    setWordWrap(next: boolean) {
      if (next === wordWrap) return;
      wordWrap = next;
      for (const view of views()) {
        view.dispatch({ effects: wrapCompartment.reconfigure(next ? EditorView.lineWrapping : []) });
      }
    },
    focus: () => editableView().focus(),
    performAction(action: string) {
      const view = editableView();
      switch (action) {
        case "diffViewerOpenFind":
          return openSearchPanel(view);
        case "diffViewerFindNext":
          return searchPanelOpen(view.state) ? findNext(view) : false;
        case "diffViewerFindPrevious":
          return searchPanelOpen(view.state) ? findPrevious(view) : false;
        case "diffViewerCloseFind":
          return closeSearchPanel(view);
        default:
          return false;
      }
    },
    destroy: teardown,
  };
}
