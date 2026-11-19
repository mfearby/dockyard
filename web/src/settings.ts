import { onNative, send, type AppSummary, type Preferences, type ScreenSpace } from './bridge.ts';
import { canMatchDock, parseBarHeight } from './prefs.ts';

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const hideHiddenApps = byId<HTMLInputElement>('hideHiddenApps');
const hideAppsWithoutWindows = byId<HTMLInputElement>('hideAppsWithoutWindows');
const separateWindows = byId<HTMLInputElement>('separateWindows');
const screenSpaceRadios = Array.from(document.querySelectorAll<HTMLInputElement>('input[name="screenSpace"]'));
const barHeight = byId<HTMLInputElement>('barHeight');
const matchDock = byId<HTMLButtonElement>('matchDock');
const axNote = byId<HTMLDivElement>('axNote');
const windowsAxNote = byId<HTMLDivElement>('windowsAxNote');
const moveAxNote = byId<HTMLDivElement>('moveAxNote');
const dockNote = byId<HTMLSpanElement>('dockNote');
const excludedList = byId<HTMLDivElement>('excludedList');
const removeExcluded = byId<HTMLButtonElement>('removeExcluded');

let accessibilityTrusted = true;
let dockHeight = 0;
let min = 28;
let max = 64;
/** Last height sent or received, used when the box holds something unusable. */
let height = 40;
let excludedApps: AppSummary[] = [];
let selectedExcluded: string | null = null;

function screenSpace(): ScreenSpace {
    return screenSpaceRadios.find((r) => r.checked)?.value === 'moveWindows' ? 'moveWindows' : 'coverDock';
}

function current(): Preferences {
    return {
        hideHiddenApps: hideHiddenApps.checked,
        hideAppsWithoutWindows: hideAppsWithoutWindows.checked,
        barHeight: height,
        screenSpace: screenSpace(),
        separateWindows: separateWindows.checked,
        excludedApps: excludedApps.map((a) => a.bundleId),
    };
}

function save() {
    send({ type: 'setPreferences', preferences: current() });
}

function updateNotes() {
    const mode = screenSpace();
    axNote.hidden = accessibilityTrusted || !hideAppsWithoutWindows.checked;
    windowsAxNote.hidden = accessibilityTrusted || !separateWindows.checked;
    moveAxNote.hidden = accessibilityTrusted || mode !== 'moveWindows';
    const matchable = canMatchDock(dockHeight, min, max);
    matchDock.disabled = mode !== 'coverDock' || !matchable || height === dockHeight;
    dockNote.textContent = matchable
        ? `The Dock takes ${dockHeight}pt at the bottom of the screen.`
        : 'The Dock isn\u2019t taking space at the bottom of the screen.';
}

onNative((msg) => {
    if (msg.type !== 'settings') return;
    hideHiddenApps.checked = msg.preferences.hideHiddenApps;
    hideAppsWithoutWindows.checked = msg.preferences.hideAppsWithoutWindows;
    separateWindows.checked = msg.preferences.separateWindows;
    for (const radio of screenSpaceRadios) radio.checked = radio.value === msg.preferences.screenSpace;
    accessibilityTrusted = msg.accessibilityTrusted;
    dockHeight = msg.dockHeight;
    min = msg.barHeightMin;
    max = msg.barHeightMax;
    height = msg.preferences.barHeight;
    barHeight.min = String(min);
    barHeight.max = String(max);
    // Don't overwrite the box while the user is typing in it.
    if (document.activeElement !== barHeight) barHeight.value = String(height);
    excludedApps = msg.excludedAppDetails;
    renderExcluded();
    updateNotes();
});

function renderExcluded() {
    if (!excludedApps.some((a) => a.bundleId === selectedExcluded)) selectedExcluded = null;
    removeExcluded.disabled = selectedExcluded === null;
    if (excludedApps.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'empty';
        empty.textContent = 'No apps. Use Add\u2026 to choose some.';
        excludedList.replaceChildren(empty);
        return;
    }
    excludedList.replaceChildren(...excludedApps.map((app) => {
        const item = document.createElement('div');
        item.className = 'item' + (app.bundleId === selectedExcluded ? ' selected' : '');
        item.dataset.id = app.bundleId;
        item.setAttribute('role', 'option');
        if (app.icon) {
            const img = document.createElement('img');
            img.src = app.icon;
            item.append(img);
        }
        const name = document.createElement('span');
        name.textContent = app.name;
        item.append(name);
        return item;
    }));
}

excludedList.addEventListener('mousedown', (e) => {
    const item = (e.target as HTMLElement).closest<HTMLElement>('.item');
    selectedExcluded = item?.dataset.id ?? null;
    renderExcluded();
});

function removeSelectedExcluded() {
    if (selectedExcluded === null) return;
    excludedApps = excludedApps.filter((a) => a.bundleId !== selectedExcluded);
    selectedExcluded = null;
    renderExcluded();
    save();
}

removeExcluded.addEventListener('click', removeSelectedExcluded);
excludedList.addEventListener('keydown', (e) => {
    if (e.key === 'Backspace' || e.key === 'Delete') removeSelectedExcluded();
});
byId('addExcluded').addEventListener('click', () => send({ type: 'chooseExcludedApp' }));

for (const input of [hideHiddenApps, hideAppsWithoutWindows, separateWindows, ...screenSpaceRadios]) {
    input.addEventListener('change', () => {
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

for (const button of Array.from(document.querySelectorAll('.grantAx'))) {
    button.addEventListener('click', () => send({ type: 'requestAccessibility' }));
}
byId('close').addEventListener('click', () => send({ type: 'closeSettings' }));

// The app has no menu bar, so handle the usual close shortcuts here.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || (e.metaKey && e.key === 'w')) send({ type: 'closeSettings' });
});

// Size the window to the content, which changes as notes appear and disappear.
new ResizeObserver(() => {
    send({ type: 'resizeSettings', height: Math.ceil(document.body.getBoundingClientRect().height) });
}).observe(document.body);

send({ type: 'getSettings' });
