// Colour palettes for OnAir. agenda.json picks one with "theme": { "preset": "<key>" } and can override any
// single colour ("ink", "navy", "accent", "accentInk"). Midnight, the blue palette, is the default.
//   ink        page background of the dark areas (header, hero, screens)
//   navy       secondary dark colour (borders, act tags)
//   accent     highlights: buttons, progress bars, countdown digits
//   accentInk  the accent darkened enough to read on a light background
export const THEMES = {
  midnight: { name: "Midnight (default)", ink: "#0F0F46", navy: "#2A2A72", accent: "#3ACEA9", accentInk: "#0E7A5E" },
  ocean:    { name: "Ocean",              ink: "#062A3A", navy: "#0E4D64", accent: "#5BC0EB", accentInk: "#1F6F99" },
  forest:   { name: "Forest",             ink: "#0B2A1F", navy: "#1E4D3A", accent: "#E9C46A", accentInk: "#8A6A12" },
  ember:    { name: "Ember",              ink: "#2A0F12", navy: "#5A1E24", accent: "#FF8A5B", accentInk: "#B4461F" },
  grape:    { name: "Grape",              ink: "#1E0B3A", navy: "#3D1F6B", accent: "#C38BFF", accentInk: "#6B2FB3" },
  graphite: { name: "Graphite",           ink: "#16181D", navy: "#2C313A", accent: "#F5C518", accentInk: "#8A6D00" },
};
export const DEFAULT_THEME = "midnight";

// The four colours for a "theme" block: the preset's, with any explicit colour on top.
export function resolveTheme(t = {}) {
  const base = THEMES[t?.preset] || THEMES[DEFAULT_THEME];
  const out = { ink: base.ink, navy: base.navy, accent: base.accent, accentInk: base.accentInk };
  for (const k of Object.keys(out)) if (typeof t?.[k] === "string" && t[k]) out[k] = t[k];
  return out;
}

// Applies a theme to the page's CSS variables (the names the pages use).
export function applyTheme(t, root = document.documentElement) {
  const c = resolveTheme(t);
  root.style.setProperty("--ink", c.ink);
  root.style.setProperty("--navy", c.navy);
  root.style.setProperty("--mint", c.accent);
  root.style.setProperty("--mint-ink", c.accentInk);
}
