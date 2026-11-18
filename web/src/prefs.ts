/**
 * Reads the taskbar height typed into the Options window.
 * Returns a whole number within [min, max], or null while the text isn't a usable number
 * (such as an empty box mid-edit), so nothing is sent until the user types something valid.
 */
export function parseBarHeight(text: string, min: number, max: number): number | null {
    if (text.trim() === '') return null;
    const value = Number(text);
    if (!Number.isFinite(value)) return null;
    return Math.min(max, Math.max(min, Math.round(value)));
}

/** Whether "Match Dock" can be offered: the Dock reserves space and that height is one the bar supports. */
export function canMatchDock(dockHeight: number, min: number, max: number): boolean {
    return dockHeight >= min && dockHeight <= max;
}
