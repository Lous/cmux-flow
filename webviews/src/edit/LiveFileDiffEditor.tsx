import { useEffect, useRef, useState } from "react";
import type { ResolvedDiffViewerAppearance } from "../appearance";
import type { DiffViewerLabelResolver } from "../labels";
import { setActiveDiffEditor } from "./active-editor";
import {
  closeLiveFileTab,
  DiffEditBridgeError,
  type LiveFile,
  type LiveFileView,
  loadLiveFile,
  reportUnsavedEdits,
  saveLiveFile,
} from "./bridge";
import type { DiffEditorHandle, DiffEditorLayout } from "./codemirror-editor";
import { editorPaletteStyle } from "./editor-palette";
import { planLiveFileUpdate } from "./live-file-plan";

type Shown = { view: LiveFileView; editable: boolean; deleted: boolean; grant?: string; sha256?: string };

type Notice =
  | { kind: "none" }
  | { kind: "saved" }
  | { kind: "error"; message: string }
  | { kind: "conflict"; currentSha256: string };

declare global {
  interface Window {
    /** Called by the app when the tab's file, the index or HEAD change. */
    __cmuxDiffEditRefresh?: () => void;
  }
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function revealInFiles(path: string): void {
  const handler = (window as any).webkit?.messageHandlers?.cmuxDiffRevealFile;
  if (handler && typeof handler.postMessage === "function") {
    handler.postMessage({ path });
  }
}

/**
 * A Source Control file tab as a live diff editor, the way VS Code's diff
 * editor works: the file opens editable against the index (read-only when the
 * tab shows staged text), Cmd+S saves, and the tab follows the file — outside
 * edits and staging changes land in place, and a file whose changes are
 * discarded or committed elsewhere closes its tab.
 */
export function LiveFileDiffEditor({
  appearance,
  label,
  layout,
  path,
  wordWrap,
}: {
  appearance: ResolvedDiffViewerAppearance;
  label: DiffViewerLabelResolver;
  layout: DiffEditorLayout;
  path: string;
  wordWrap: boolean;
}) {
  const layerRef = useRef<HTMLElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const handleRef = useRef<DiffEditorHandle | null>(null);
  const shownRef = useRef<Shown | null>(null);
  const hadChangesRef = useRef(false);
  const savedContentRef = useRef<string | null>(null);
  const loadingRef = useRef(false);
  const reloadAgainRef = useRef(false);
  const savingRef = useRef(false);
  const layoutRef = useRef(layout);
  const wordWrapRef = useRef(wordWrap);
  const revertLabelRef = useRef(label("editRevertChange"));
  const [phase, setPhase] = useState<"opening" | "ready" | "failed">("opening");
  const [failure, setFailure] = useState("");
  const [shown, setShown] = useState<Shown | null>(null);
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState<Notice>({ kind: "none" });

  const show = (next: Shown) => {
    shownRef.current = next;
    setShown(next);
  };

  /** Applies the file's newest state to the editor (creating it on first load). */
  const applyLoaded = async (next: LiveFile) => {
    if (next.view !== "clean") {
      hadChangesRef.current = true;
    }
    const handle = handleRef.current;
    const current = shownRef.current;
    const keepSha = handle?.isDirty() === true;
    const shownNext: Shown = {
      view: next.view,
      editable: next.editable,
      deleted: next.deleted,
      grant: next.grant,
      // With unsaved edits the old hash stays, so saving over outside changes conflicts.
      sha256: keepSha ? current?.sha256 : next.sha256,
    };
    if (handle == null || current == null) {
      const editorModule = await import("./codemirror-editor");
      if (containerRef.current == null || handleRef.current != null) {
        return;
      }
      handleRef.current = editorModule.createDiffEditor({
        parent: containerRef.current,
        path,
        content: next.content,
        base: next.base,
        editable: next.editable,
        layout: layoutRef.current,
        wordWrap: wordWrapRef.current,
        labels: { revertChange: revertLabelRef.current },
        onDirtyChange: (nextDirty) => {
          setDirty(nextDirty);
          if (nextDirty) {
            setNotice((existing) => (existing.kind === "saved" ? { kind: "none" } : existing));
          }
          void reportUnsavedEdits(nextDirty).catch(() => {});
        },
        onSave: () => void save(),
      });
      show(shownNext);
      setPhase("ready");
      return;
    }
    const update = planLiveFileUpdate(current, next, {
      dirty: handle.isDirty(),
      hadChanges: hadChangesRef.current,
      savedContent: savedContentRef.current,
    });
    switch (update.kind) {
      case "close":
        if (await closeLiveFileTab().catch(() => false)) {
          return;
        }
        handle.applyExternal(next.content, next.base);
        break;
      case "reset":
        handle.reset(next.content, next.base, next.editable);
        break;
      case "apply":
        handle.applyExternal(next.content, next.base);
        break;
      case "setBase":
        handle.setBase(next.base);
        break;
      case "keep":
        return;
    }
    show(update.kind === "setBase" ? { ...shownNext, view: current.view, editable: current.editable } : shownNext);
  };

  /** Loads the file's newest state; refreshes that arrive meanwhile run once more after. */
  const refresh = async () => {
    if (loadingRef.current) {
      reloadAgainRef.current = true;
      return;
    }
    loadingRef.current = true;
    try {
      do {
        reloadAgainRef.current = false;
        await applyLoaded(await loadLiveFile());
      } while (reloadAgainRef.current);
    } catch (error) {
      if (handleRef.current == null) {
        setFailure(messageOf(error));
        setPhase("failed");
      } else {
        setNotice({ kind: "error", message: messageOf(error) });
      }
    } finally {
      loadingRef.current = false;
    }
  };

  // Reads only refs and state setters, so the copy CodeMirror's Cmd+S keeps stays valid.
  const save = async (expectedSha256?: string): Promise<boolean> => {
    const handle = handleRef.current;
    const current = shownRef.current;
    if (handle == null || current?.grant == null || current.sha256 == null || savingRef.current || !current.editable) {
      return false;
    }
    savingRef.current = true;
    setSaving(true);
    const content = handle.getContent();
    try {
      const sha256 = await saveLiveFile(current.grant, content, expectedSha256 ?? current.sha256);
      savedContentRef.current = content;
      show({ ...current, sha256 });
      handle.markSaved(content);
      setNotice({ kind: "saved" });
      return true;
    } catch (error) {
      if (error instanceof DiffEditBridgeError && error.code === "conflict" && error.currentSha256) {
        setNotice({ kind: "conflict", currentSha256: error.currentSha256 });
      } else {
        setNotice({ kind: "error", message: messageOf(error) });
      }
      return false;
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  };

  /** Drops unsaved edits and shows the file as it is on disk. */
  const reloadFromDisk = async () => {
    try {
      const next = await loadLiveFile();
      handleRef.current?.reset(next.content, next.base, next.editable);
      show({ view: next.view, editable: next.editable, deleted: next.deleted, grant: next.grant, sha256: next.sha256 });
      setNotice({ kind: "none" });
    } catch (error) {
      setNotice({ kind: "error", message: messageOf(error) });
    }
  };

  // The app calls back through this ref, so the mount effect never re-runs.
  const refreshRef = useRef(refresh);
  useEffect(() => {
    refreshRef.current = refresh;
  });

  useEffect(() => {
    setActiveDiffEditor({ performAction: (action) => handleRef.current?.performAction(action) ?? false });
    window.__cmuxDiffEditRefresh = () => void refreshRef.current();
    void refreshRef.current();
    return () => {
      delete window.__cmuxDiffEditRefresh;
      setActiveDiffEditor(null);
      handleRef.current?.destroy();
      handleRef.current = null;
    };
    // The editor is bound to one file for the page's life.
  }, [path]);

  useEffect(() => {
    layoutRef.current = layout;
    handleRef.current?.setLayout(layout);
  }, [layout]);

  useEffect(() => {
    wordWrapRef.current = wordWrap;
    handleRef.current?.setWordWrap(wordWrap);
  }, [wordWrap]);

  // VS Code marks a dirty editor's tab; the tab title follows the page title.
  useEffect(() => {
    const title = document.title.replace(/^● /, "");
    document.title = dirty ? `● ${title}` : title;
  }, [dirty]);

  useEffect(() => {
    const layer = layerRef.current;
    if (layer == null) {
      return;
    }
    // The viewer's own shortcuts (find, Escape) listen on the document; keys
    // typed here belong to the editor. Cmd+S also saves outside the text.
    const onKeyDown = (event: KeyboardEvent) => {
      event.stopPropagation();
      if ((event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void save();
      }
    };
    layer.addEventListener("keydown", onKeyDown);
    return () => layer.removeEventListener("keydown", onKeyDown);
  });

  const viewLabel = shown == null
    ? ""
    : shown.deleted
      ? label("editDeleted")
      : shown.view === "staged"
        ? label("editStagedReadOnly")
        : shown.view === "clean"
          ? label("editNoChanges")
          : label("editWorkingTree");
  const status = saving
    ? label("editSaving")
    : dirty
      ? label("editUnsaved")
      : notice.kind === "saved"
        ? label("editSaved")
        : "";

  return (
    <section
      ref={layerRef}
      id="diff-editor-layer"
      aria-label={path}
      data-dirty={dirty ? "true" : "false"}
      data-view={shown?.view ?? ""}
      style={editorPaletteStyle(appearance) as React.CSSProperties}
    >
      <header className="diff-editor-toolbar">
        <span className="diff-editor-path" title={path}>{path}</span>
        {viewLabel !== "" ? <span className="diff-editor-view">{viewLabel}</span> : null}
        <output className="diff-editor-status">{status}</output>
        <span className="diff-editor-spacer" />
        <button type="button" className="file-review-load" onClick={() => revealInFiles(path)}>
          {label("showInFiles")}
        </button>
      </header>
      {notice.kind === "conflict" ? (
        <div className="diff-editor-notice" data-kind="conflict" role="alert">
          <span>{label("editConflict")}</span>
          <button type="button" className="file-review-load" onClick={() => void reloadFromDisk()}>
            {label("editReload")}
          </button>
          <button type="button" className="file-review-load" onClick={() => void save(notice.currentSha256)}>
            {label("editOverwrite")}
          </button>
        </div>
      ) : null}
      {notice.kind === "error" ? (
        <div className="diff-editor-notice" data-kind="error" role="alert">
          <span>{notice.message}</span>
        </div>
      ) : null}
      <div className="diff-editor-body" ref={containerRef} />
      {phase === "opening" ? <div className="diff-editor-placeholder">{label("editOpening")}</div> : null}
      {phase === "failed" ? <div className="diff-editor-placeholder" role="alert">{failure}</div> : null}
    </section>
  );
}
