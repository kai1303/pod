export const inkColors = [
  { name: "Ink", hex: "#18181B" },
  { name: "Blue", hex: "#2563EB" },
  { name: "Green", hex: "#15803D" },
  { name: "Red", hex: "#DC2626" },
  { name: "Orange", hex: "#C2410C" },
  { name: "Purple", hex: "#7C3AED" },
  { name: "Pink", hex: "#BE185D" },
  { name: "Gray", hex: "#64748B" },
];
export const highlightColors = [
  { name: "Yellow", hex: "#FACC15" },
  { name: "Mint", hex: "#86EFAC" },
  { name: "Sky", hex: "#7DD3FC" },
  { name: "Rose", hex: "#F9A8D4" },
  { name: "Peach", hex: "#FDBA74" },
  { name: "Lavender", hex: "#C4B5FD" },
];
export function normalizeHex(value: string): string | null {
  const hex = value.trim().replace(/^#/, "");
  if (/^[a-f\d]{3}$/i.test(hex))
    return (
      "#" +
      [...hex]
        .map((c) => c + c)
        .join("")
        .toUpperCase()
    );
  return /^[a-f\d]{6}$/i.test(hex) ? "#" + hex.toUpperCase() : null;
}
export function contrastingText(hex: string) {
  const rgb = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const luminance = rgb.map((c) =>
    c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4,
  );
  return luminance[0] * 0.2126 + luminance[1] * 0.7152 + luminance[2] * 0.0722 >
    0.179
    ? "#111111"
    : "#FFFFFF";
}
