import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { JSDOM } from "jsdom";
import { resolveDiffViewerAppearance } from "../src/appearance";
import { editorPaletteStyle, editorTokenVariable } from "../src/edit/editor-palette";

const globalKeys = [
  "window",
  "document",
  "navigator",
  "MutationObserver",
  "requestAnimationFrame",
  "cancelAnimationFrame",
  "getComputedStyle",
  "HTMLElement",
  "Node",
  "KeyboardEvent",
] as const;
let dom: JSDOM | null = null;
const saved = new Map<string, unknown>();

beforeEach(() => {
  dom = new JSDOM("<!doctype html><body><div id=host></div></body>", { pretendToBeVisual: true });
  for (const key of globalKeys) {
    saved.set(key, (globalThis as any)[key]);
    const value = (dom.window as any)[key];
    Object.defineProperty(globalThis, key, {
      configurable: true,
      writable: true,
      value: typeof value === "function" && key !== "HTMLElement" && key !== "Node" && key !== "MutationObserver" && key !== "KeyboardEvent"
        ? value.bind(dom.window)
        : value,
    });
  }
});

afterEach(() => {
  for (const key of globalKeys) {
    Object.defineProperty(globalThis, key, { configurable: true, writable: true, value: saved.get(key) });
  }
  dom?.window.close();
  dom = null;
});

async function makeEditor(content: string, base: string, layout: "split" | "unified" = "unified", writable = true) {
  const { createDiffEditor } = await import("../src/edit/codemirror-editor");
  const { EditorView } = await import("@codemirror/view");
  const parent = document.getElementById("host")!;
  const dirtyChanges: boolean[] = [];
  let saves = 0;
  const handle = createDiffEditor({
    parent,
    path: "src/example.ts",
    content,
    base,
    editable: writable,
    layout,
    wordWrap: false,
    labels: { revertChange: "Revert" },
    onDirtyChange: (dirty) => dirtyChanges.push(dirty),
    onSave: () => {
      saves += 1;
    },
  });
  const editable = () => {
    const contents = Array.from(parent.querySelectorAll(".cm-content")) as HTMLElement[];
    return EditorView.findFromDOM(contents[contents.length - 1])!;
  };
  return { handle, parent, editable, dirtyChanges, saves: () => saves };
}

describe("editorPaletteStyle", () => {
  test("colors syntax roles with the terminal palette, per color scheme", () => {
    const appearance = resolveDiffViewerAppearance({
      themes: {
        light: { background: "#ffffff", foreground: "#111111", palette: { "2": "#116611", "5": "#771177" }, type: "light" },
        dark: { background: "#000000", foreground: "#eeeeee", palette: { "2": "#88ee88", "5": "#ee88ee" }, type: "dark" },
      },
    });
    const style = editorPaletteStyle(appearance);
    expect(style[editorTokenVariable("string")]).toBe("light-dark(#116611, #88ee88)");
    expect(style[editorTokenVariable("keyword")]).toBe("light-dark(#771177, #ee88ee)");
    // A role with no palette color falls back to the foreground.
    expect(style[editorTokenVariable("function")]).toBe("light-dark(#111111, #eeeeee)");
  });
});

describe("createDiffEditor", () => {
  test("keeps CRLF line endings and starts clean", async () => {
    const content = "one\r\ntwo changed\r\nthree\r\n";
    const { handle } = await makeEditor(content, "one\r\ntwo\r\nthree\r\n");
    expect(handle.getContent()).toBe(content);
    expect(handle.isDirty()).toBe(false);
    handle.destroy();
  });

  test("tracks unsaved edits against what was last saved", async () => {
    const { handle, editable, dirtyChanges } = await makeEditor("a\nb\n", "a\n");
    const view = editable();
    view.dispatch({ changes: { from: view.state.doc.length, insert: "c\n" } });
    expect(handle.isDirty()).toBe(true);
    expect(dirtyChanges).toEqual([true]);

    handle.markSaved(handle.getContent());
    expect(handle.isDirty()).toBe(false);
    expect(dirtyChanges).toEqual([true, false]);

    // Typing back to the saved text is clean again.
    view.dispatch({ changes: { from: 0, insert: "x" } });
    view.dispatch({ changes: { from: 0, to: 1 } });
    expect(handle.isDirty()).toBe(false);
    handle.destroy();
  });

  test("Mod-s saves instead of reaching the page", async () => {
    const { handle, editable, saves } = await makeEditor("a\n", "");
    // CodeMirror's "Mod" is Cmd on macOS and Ctrl elsewhere (jsdom).
    const event = new KeyboardEvent("keydown", { key: "s", ctrlKey: true, bubbles: true, cancelable: true });
    editable().contentDOM.dispatchEvent(event);
    expect(saves()).toBe(1);
    expect(event.defaultPrevented).toBe(true);
    handle.destroy();
  });

  test("split layout shows a read-only base beside the editable file; switching keeps the text", async () => {
    const { handle, parent, editable } = await makeEditor("a\nB\n", "a\nb\n", "split");
    expect(parent.querySelectorAll(".cm-editor").length).toBe(2);
    const { EditorView } = await import("@codemirror/view");
    const base = EditorView.findFromDOM(parent.querySelector(".cm-merge-a .cm-content") as HTMLElement)!;
    expect(base.state.readOnly).toBe(true);
    expect(base.state.doc.toString()).toBe("a\nb\n");

    const view = editable();
    view.dispatch({ changes: { from: view.state.doc.length, insert: "c\n" } });
    handle.setLayout("unified");
    expect(parent.querySelectorAll(".cm-editor").length).toBe(1);
    expect(handle.getContent()).toBe("a\nB\nc\n");
    expect(handle.isDirty()).toBe(true);
    handle.destroy();
    expect(parent.childElementCount).toBe(0);
  });

  test("takes outside changes in place, keeping the cursor", async () => {
    const { handle, editable } = await makeEditor("one\ntwo\nthree\n", "one\n");
    const view = editable();
    view.dispatch({ selection: { anchor: view.state.doc.line(3).from + 2 } });
    // An agent inserts a line above the cursor; the index gains a line too.
    handle.applyExternal("zero\none\ntwo\nthree\n", "zero\none\n");
    expect(handle.getContent()).toBe("zero\none\ntwo\nthree\n");
    expect(view.state.doc.lineAt(view.state.selection.main.head).number).toBe(4);
    expect(view.state.selection.main.head - view.state.doc.line(4).from).toBe(2);
    expect(handle.isDirty()).toBe(false);
    handle.destroy();
  });

  test("keeps CRLF when outside changes arrive", async () => {
    const { handle } = await makeEditor("a\r\nb\r\n", "a\r\n");
    handle.applyExternal("a\r\nb\r\nc\r\n", "a\r\n");
    expect(handle.getContent()).toBe("a\r\nb\r\nc\r\n");
    handle.destroy();
  });

  test("a new comparison text leaves unsaved edits alone", async () => {
    const { handle, editable } = await makeEditor("a\nb\n", "a\n", "split");
    const view = editable();
    view.dispatch({ changes: { from: 0, insert: "typed " } });
    handle.setBase("a\nb\n");
    expect(handle.getContent()).toBe("typed a\nb\n");
    expect(handle.isDirty()).toBe(true);
    handle.destroy();
  });

  test("a read-only right side refuses typing but keeps its text selectable", async () => {
    const { handle, editable, parent } = await makeEditor("index\n", "head\n", "unified", false);
    expect(editable().state.readOnly).toBe(true);
    expect(parent.querySelector(".cmux-edit-revert-marker")).toBeNull();
    handle.reset("disk\n", "index\n", true);
    expect(editable().state.readOnly).toBe(false);
    expect(handle.getContent()).toBe("disk\n");
    handle.destroy();
  });

  test("unified view reverts a change from the gutter, never over the code", async () => {
    const { handle, parent, editable } = await makeEditor("one\nTWO\nthree\nfour\nadded\n", "one\ntwo\nthree\nfour\n");
    const markers = () => Array.from(parent.querySelectorAll(".cmux-edit-revert-marker[role=button]")) as HTMLElement[];
    expect(parent.querySelector(".cm-chunkButtons")).toBeNull();
    // One beside the removed "two", one beside the line that was only added.
    expect(markers().length).toBe(2);
    expect(markers()[0].getAttribute("aria-label")).toBe("Revert");
    markers()[0].dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true, cancelable: true }));
    expect(handle.getContent()).toBe("one\ntwo\nthree\nfour\nadded\n");
    expect(handle.isDirty()).toBe(true);
    expect(markers().length).toBe(1);
    markers()[0].dispatchEvent(new window.MouseEvent("mousedown", { bubbles: true, cancelable: true }));
    expect(handle.getContent()).toBe("one\ntwo\nthree\nfour\n");
    expect(markers().length).toBe(0);
    const { undo } = await import("@codemirror/commands");
    undo(editable());
    undo(editable());
    expect(handle.getContent()).toBe("one\nTWO\nthree\nfour\nadded\n");
    handle.destroy();
  });

  test("split view keeps its own revert arrows between the sides", async () => {
    const { handle, parent } = await makeEditor("a\nB\n", "a\nb\n", "split");
    expect(parent.querySelector(".cmux-edit-revert-marker")).toBeNull();
    // MergeView draws its arrows on its next measure pass.
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    expect(parent.querySelector(".cm-merge-revert button")).not.toBeNull();
    handle.destroy();
  });

  test("routes viewer find actions to the editor's search panel", async () => {
    const { handle, parent } = await makeEditor("needle\n", "");
    expect(handle.performAction("diffViewerNextFile")).toBe(false);
    expect(handle.performAction("diffViewerOpenFind")).toBe(true);
    expect(parent.querySelector(".cm-search")).not.toBeNull();
    expect(handle.performAction("diffViewerCloseFind")).toBe(true);
    expect(parent.querySelector(".cm-search")).toBeNull();
    handle.destroy();
  });
});
