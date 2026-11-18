import { onNative, send, type Preferences } from './bridge.ts';
import { canMatchDock, parseBarHeight } from './prefs.ts';

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const hideHiddenApps = byId<HTMLInputElement>('hideHiddenApps');
const hideAppsWithoutWindows = byId<HTMLInputElement>('hideAppsWithoutWindows');
const barHeight = byId<HTMLInputElement>('barHeight');
const matchDock = byId<HTMLButtonElement>('matchDock');
const axNote = byId<HTMLDivElement>('axNote');
const dockNote = byId<HTMLDivElement>('dockNote');

let accessibilityTrusted = true;
let dockHeight = 0;
let min = 28;
let max = 64;
/** Last height sent or received, used when the box holds something unusable. */
let height = 40;

function current(): Preferences {
    return {
        hideHiddenApps: hideHiddenApps.checked,
        hideAppsWithoutWindows: hideAppsWithoutWindows.checked,
        barHeight: height,
    };
}

function save() {
    send({ type: 'setPreferences', preferences: current() });
}

function updateNotes() {
    axNote.hidden = accessibilityTrusted || !hideAppsWithoutWindows.checked;
    const matchable = canMatchDock(dockHeight, min, max);
    matchDock.disabled = !matchable || height === dockHeight;
    dockNote.textContent = matchable
        ? `The Dock reserves ${dockHeight}pt at the bottom of the screen.`
        : 'The Dock isn\u2019t reserving space at the bottom of the screen, so there\u2019s nothing to match.';
}

onNative((msg) => {
    if (msg.type !== 'settings') return;
    hideHiddenApps.checked = msg.preferences.hideHiddenApps;
    hideAppsWithoutWindows.checked = msg.preferences.hideAppsWithoutWindows;
    accessibilityTrusted = msg.accessibilityTrusted;
    dockHeight = msg.dockHeight;
    min = msg.barHeightMin;
    max = msg.barHeightMax;
    height = msg.preferences.barHeight;
    barHeight.min = String(min);
    barHeight.max = String(max);
    // Don't overwrite the box while the user is typing in it.
    if (document.activeElement !== barHeight) barHeight.value = String(height);
    updateNotes();
});

for (const box of [hideHiddenApps, hideAppsWithoutWindows]) {
    box.addEventListener('change', () => {
        updateNotes();
        save();
    });
}

function applyHeight(value: number | null) {
    if (value === null || value === height) return;
    height = value;
    updateNotes();
    save();
}

// Apply as the user types or uses the arrows, so they can watch the bar resize. Values outside the
// range are skipped here, so typing "36" doesn't briefly clamp "3" up to the minimum.
barHeight.addEventListener('input', () => {
    const value = parseBarHeight(barHeight.value, min, max);
    if (value !== null && value === Math.round(Number(barHeight.value))) applyHeight(value);
});

// On Return or leaving the box, apply the clamped value and show it.
barHeight.addEventListener('change', () => {
    applyHeight(parseBarHeight(barHeight.value, min, max));
    barHeight.value = String(height);
});

matchDock.addEventListener('click', () => {
    height = dockHeight;
    barHeight.value = String(height);
    updateNotes();
    save();
});

byId('grantAx').addEventListener('click', () => send({ type: 'requestAccessibility' }));
byId('close').addEventListener('click', () => send({ type: 'closeSettings' }));

// The app has no menu bar, so handle the usual close shortcuts here.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || (e.metaKey && e.key === 'w')) send({ type: 'closeSettings' });
});

send({ type: 'getSettings' });
