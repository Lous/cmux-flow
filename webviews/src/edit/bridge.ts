import { makeClientId } from "../agent-session/shared/ids";

type NativeReply<T> =
  | { ok: true; value: T }
  | { ok: false; error?: { code?: string; userMessage?: string; currentSha256?: string } };

type DiffEditMessageHandler = {
  postMessage(message: unknown): Promise<NativeReply<unknown>>;
};

/** Which comparison a live diff tab shows, like VS Code's "(Working Tree)" / "(Index)". */
export type LiveFileView = "workingTree" | "staged" | "clean";

/** A Source Control file tab's file as it is now. */
export type LiveFile = {
  view: LiveFileView;
  /** Left side: the index, HEAD, or empty for a file Git never recorded. */
  base: string;
  /** Right side: the file on disk, or the index when staged. */
  content: string;
  /** False for staged text, a deleted file, or anything the app will not write. */
  editable: boolean;
  deleted: boolean;
  /** Present when `editable`. */
  grant?: string;
  /** SHA-256 of the file on disk, present when `editable`. */
  sha256?: string;
};

export class DiffEditBridgeError extends Error {
  readonly code?: string;
  /** Set for `conflict`: the hash of what is on disk now. */
  readonly currentSha256?: string;

  constructor(message: string, code?: string, currentSha256?: string) {
    super(message);
    this.name = "DiffEditBridgeError";
    this.code = code;
    this.currentSha256 = currentSha256;
  }
}

function diffEditHandler(): DiffEditMessageHandler | null {
  if (typeof window === "undefined") {
    return null;
  }
  const handler = (window as any).webkit?.messageHandlers?.cmuxDiffEdit;
  return handler != null && typeof handler.postMessage === "function" ? handler : null;
}

export function diffEditBridgeAvailable(): boolean {
  return diffEditHandler() != null;
}

async function callDiffEdit<T>(method: string, params: Record<string, unknown>): Promise<T> {
  const handler = diffEditHandler();
  if (handler == null) {
    throw new DiffEditBridgeError("Editing is unavailable.");
  }
  const reply = (await handler.postMessage({ id: makeClientId(), method, params })) as NativeReply<T>;
  if (!reply.ok) {
    throw new DiffEditBridgeError(
      reply.error?.userMessage || "Edit request failed.",
      reply.error?.code,
      reply.error?.currentSha256,
    );
  }
  return reply.value;
}

/**
 * Whether this page is a Source Control file tab, which the app keeps live:
 * it calls `window.__cmuxDiffEditRefresh()` when the file, the index or HEAD change.
 */
export async function startLiveFileSession(): Promise<{ live: boolean; path?: string }> {
  const value = await callDiffEdit<{ live?: boolean; path?: string }>("edit.session", {});
  return { live: value?.live === true, path: typeof value?.path === "string" ? value.path : undefined };
}

export function loadLiveFile(): Promise<LiveFile> {
  return callDiffEdit<LiveFile>("edit.load", {});
}

/** Writes `content`; rejects with code `conflict` when the file changed since `expectedSha256`. */
export async function saveLiveFile(grant: string, content: string, expectedSha256: string): Promise<string> {
  const value = await callDiffEdit<{ sha256: string }>("edit.save", { grant, content, expectedSha256 });
  return value.sha256;
}

/** Tells the app whether the page holds unsaved edits (pins the preview, asks before closing). */
export async function reportUnsavedEdits(dirty: boolean): Promise<void> {
  await callDiffEdit("edit.dirty", { dirty });
}

/** Asks the app to close this tab; it refuses while edits are unsaved. */
export async function closeLiveFileTab(): Promise<boolean> {
  const value = await callDiffEdit<{ closed?: boolean }>("edit.closeTab", {});
  return value?.closed === true;
}
