// Helpers for app button colours. Pure, so they can be unit tested.

export type RGB = [number, number, number];

/** Parses "#rrggbb" (any case, surrounding spaces allowed); null for anything else. */
export function parseHex(hex: string): RGB | null {
    const m = /^#([0-9a-f]{6})$/i.exec(hex.trim());
    if (!m) return null;
    const n = parseInt(m[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function toHex([r, g, b]: RGB): string {
    return '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
}

/** `a` moved `amount` (0 to 1) of the way towards `b`. Null if either can't be parsed. */
export function blend(a: string, b: string, amount: number): string | null {
    const x = parseHex(a);
    const y = parseHex(b);
    if (!x || !y) return null;
    const t = Math.min(1, Math.max(0, amount));
    return toHex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]);
}

/** The average of two colours: roughly how a fine chequer of the two looks. Null if either can't be parsed. */
export function mix(a: string, b: string): string | null {
    return blend(a, b, 0.5);
}

/** WCAG relative luminance: 0 for black, 1 for white. */
export function luminance([r, g, b]: RGB): number {
    const linear = (v: number) => {
        const c = v / 255;
        return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

/** Black or white, whichever is easier to read on `background`. Black if the colour can't be parsed. */
export function textOn(background: string): '#000000' | '#ffffff' {
    const rgb = parseHex(background);
    if (!rgb) return '#000000';
    const l = luminance(rgb);
    const onBlack = (l + 0.05) / 0.05;
    const onWhite = 1.05 / (l + 0.05);
    return onBlack >= onWhite ? '#000000' : '#ffffff';
}
