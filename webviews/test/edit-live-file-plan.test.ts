import { describe, expect, test } from "bun:test";
import type { LiveFile } from "../src/edit/bridge";
import { planLiveFileUpdate } from "../src/edit/live-file-plan";

const file = (overrides: Partial<LiveFile>): LiveFile => ({
  view: "workingTree",
  base: "base\n",
  content: "disk\n",
  editable: true,
  deleted: false,
  ...overrides,
});
const clean = { dirty: false, hadChanges: true, savedContent: null };

describe("planLiveFileUpdate", () => {
  test("outside edits land in place", () => {
    expect(planLiveFileUpdate({ view: "workingTree", editable: true }, file({}), clean)).toEqual({ kind: "apply" });
  });

  test("unstaging a staged tab makes it editable without reopening", () => {
    const next = file({ view: "workingTree", editable: true });
    expect(planLiveFileUpdate({ view: "staged", editable: false }, next, clean)).toEqual({ kind: "reset" });
  });

  test("discarding every change elsewhere closes the tab", () => {
    const next = file({ view: "clean", base: "base\n", content: "base\n" });
    expect(planLiveFileUpdate({ view: "workingTree", editable: true }, next, clean)).toEqual({ kind: "close" });
  });

  test("a tab never closes over unsaved edits", () => {
    const next = file({ view: "clean", base: "base\n", content: "base\n" });
    const context = { ...clean, dirty: true };
    expect(planLiveFileUpdate({ view: "workingTree", editable: true }, next, context)).toEqual({ kind: "setBase" });
  });

  test("a file this tab saved back to the original stays open", () => {
    const next = file({ view: "clean", base: "base\n", content: "base\n" });
    const context = { ...clean, savedContent: "base\n" };
    expect(planLiveFileUpdate({ view: "workingTree", editable: true }, next, context)).toEqual({ kind: "apply" });
  });

  test("a file opened without changes stays open", () => {
    const next = file({ view: "clean", base: "same\n", content: "same\n" });
    const context = { ...clean, hadChanges: false };
    expect(planLiveFileUpdate({ view: "clean", editable: true }, next, context)).toEqual({ kind: "apply" });
  });

  test("unsaved edits only take the new comparison text", () => {
    expect(planLiveFileUpdate({ view: "workingTree", editable: true }, file({}), { ...clean, dirty: true }))
      .toEqual({ kind: "setBase" });
  });
});
