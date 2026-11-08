import type { ResolvedDiffViewerAppearance } from "../appearance";
import { shikiThemeFromGhostty } from "../pierre-options";

/**
 * Syntax roles the editor colors, keyed by the first TextMate scope of the
 * matching rule in the terminal-derived Shiki theme, so the editor and the
 * diff view color the same code the same way.
 */
const TOKEN_SCOPES = {
  comment: "comment",
  string: "string",
  constant: "constant.numeric",
  keyword: "keyword",
  function: "entity.name.function",
  type: "entity.name.type",
  heading: "markup.heading",
  bold: "markup.bold",
  italic: "markup.italic",
  raw: "markup.inline.raw",
  link: "markup.underline.link",
  quote: "markup.quote",
  list: "markup.list",
  invalid: "invalid",
} as const;

export type EditorTokenRole = keyof typeof TOKEN_SCOPES;

/** The CSS custom property an editor color role is published under. */
export function editorTokenVariable(role: EditorTokenRole | "fg"): string {
  return `--cmux-edit-${role}`;
}

type ShikiTokenRule = { scope?: string | string[]; settings?: { foreground?: string } };

function roleColors(theme: { tokenColors: ShikiTokenRule[] }, foreground: string): Record<EditorTokenRole, string> {
  const colors = {} as Record<EditorTokenRole, string>;
  for (const [role, scope] of Object.entries(TOKEN_SCOPES) as [EditorTokenRole, string][]) {
    const rule = theme.tokenColors.find((candidate) => {
      const scopes = Array.isArray(candidate.scope) ? candidate.scope : candidate.scope ? [candidate.scope] : [];
      return scopes[0] === scope;
    });
    colors[role] = rule?.settings?.foreground ?? foreground;
  }
  return colors;
}

/**
 * CSS custom properties carrying the editor's syntax colors for both color
 * schemes as `light-dark()` pairs; set them on the editor's container.
 */
export function editorPaletteStyle(appearance: ResolvedDiffViewerAppearance): Record<string, string> {
  const light = shikiThemeFromGhostty(appearance.themes.light, appearance) as any;
  const dark = shikiThemeFromGhostty(appearance.themes.dark, appearance) as any;
  const lightForeground = light.colors["editor.foreground"] as string;
  const darkForeground = dark.colors["editor.foreground"] as string;
  const lightColors = roleColors(light, lightForeground);
  const darkColors = roleColors(dark, darkForeground);
  const style: Record<string, string> = {
    [editorTokenVariable("fg")]: `light-dark(${lightForeground}, ${darkForeground})`,
  };
  for (const role of Object.keys(TOKEN_SCOPES) as EditorTokenRole[]) {
    style[editorTokenVariable(role)] = `light-dark(${lightColors[role]}, ${darkColors[role]})`;
  }
  return style;
}
