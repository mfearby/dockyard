import {
    onNative, send, type AppList, type AppSummary, type FolderSummary, type Preferences, type ScreenSpace, type Theme,
} from './bridge.ts';
import { canMatchDock, parseBarHeight } from './prefs.ts';

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const hideHiddenApps = byId<HTMLInputElement>('hideHiddenApps');
const hideAppsWithoutWindows = byId<HTMLInputElement>('hideAppsWithoutWindows');
const separateWindows = byId<HTMLInputElement>('separateWindows');
const screenSpaceRadios = Array.from(document.querySelectorAll<HTMLInputElement>('input[name="screenSpace"]'));
const themeRadios = Array.from(document.querySelectorAll<HTMLInputElement>('input[name="theme"]'));
const barHeight = byId<HTMLInputElement>('barHeight');
const matchDock = byId<HTMLButtonElement>('matchDock');
const axNote = byId<HTMLDivElement>('axNote');
const windowsAxNote = byId<HTMLDivElement>('windowsAxNote');
const moveAxNote = byId<HTMLDivElement>('moveAxNote');
const dockNote = byId<HTMLSpanElement>('dockNote');

let accessibilityTrusted = true;
let dockHeight = 0;
let min = 28;
let max = 64;
/** Last height sent or received, used when the box holds something unusable. */
let height = 40;

/** An entry in one of the Options lists: an app (id is its bundle ID) or a folder (id is its path). */
interface ListItem {
    id: string;
    name: string;
    icon: string;
}

const fromApp = (a: AppSummary): ListItem => ({ id: a.bundleId, name: a.name, icon: a.icon });
const fromFolder = (f: FolderSummary): ListItem => ({ id: f.path, name: f.name, icon: f.icon });

/** One of the Options window's lists: a list box with Add… and Remove. Add… asks Swift to show its app menu or
 *  folder picker; Swift adds the item and sends the settings back. Remove edits the list here and saves it. */
class AppListBox {
    items: ListItem[] = [];
    private selected: string | null = null;
    private readonly listEl: HTMLElement;
    private readonly removeEl: HTMLButtonElement;

    constructor(root: HTMLElement, readonly list: AppList, private readonly emptyText: string) {
        this.listEl = root.querySelector<HTMLElement>('.listbox')!;
        this.removeEl = root.querySelector<HTMLButtonElement>('.remove')!;
        this.listEl.addEventListener('mousedown', (e) => {
            const item = (e.target as HTMLElement).closest<HTMLElement>('.item');
            this.selected = item?.dataset.id ?? null;
            this.render();
        });
        this.listEl.addEventListener('keydown', (e) => {
            if (e.key === 'Backspace' || e.key === 'Delete') this.removeSelected();
        });
        this.removeEl.addEventListener('click', () => this.removeSelected());
        root.querySelector('.add')!.addEventListener('click', () => send({ type: 'chooseApp', list }));
    }

    set(items: ListItem[]) {
        this.items = items;
        this.render();
    }

    ids(): string[] {
        return this.items.map((i) => i.id);
    }

    private removeSelected() {
        if (this.selected === null) return;
        this.items = this.items.filter((i) => i.id !== this.selected);
        this.selected = null;
        this.render();
        save();
    }

    private render() {
        if (!this.items.some((i) => i.id === this.selected)) this.selected = null;
        this.removeEl.disabled = this.selected === null;
        if (this.items.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'empty';
            empty.textContent = this.emptyText;
            this.listEl.replaceChildren(empty);
            return;
        }
        this.listEl.replaceChildren(...this.items.map((app) => {
            const item = document.createElement('div');
            item.className = 'item' + (app.id === this.selected ? ' selected' : '');
            item.dataset.id = app.id;
            item.title = app.id.startsWith('/') ? app.id : '';  // a folder's full path on hover
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
}

const appListRoot = (list: AppList) => document.querySelector<HTMLElement>(`.applist[data-list="${list}"]`)!;
const noApps = 'No apps. Use Add\u2026 to choose some.';
const quickLaunch = new AppListBox(appListRoot('quickLaunch'), 'quickLaunch', noApps);
const excludedApps = new AppListBox(appListRoot('excludedApps'), 'excludedApps', noApps);
const menuApps = new AppListBox(appListRoot('menuApps'), 'menuApps', noApps);
const menuFolders = new AppListBox(appListRoot('menuFolders'), 'menuFolders', 'No folders. Use Add\u2026 to choose some.');

// Tabs. All panels share one grid cell, so the window is as tall as the tallest and doesn't resize on switching.
const tabs = Array.from(document.querySelectorAll<HTMLButtonElement>('.tab'));
const panels = Array.from(document.querySelectorAll<HTMLElement>('.panel'));

function selectTab(name: string) {
    for (const tab of tabs) {
        const on = tab.dataset.tab === name;
        tab.classList.toggle('selected', on);
        tab.setAttribute('aria-selected', String(on));
        tab.tabIndex = on ? 0 : -1;
    }
    for (const panel of panels) panel.classList.toggle('inactive', panel.dataset.panel !== name);
}

for (const tab of tabs) tab.addEventListener('click', () => selectTab(tab.dataset.tab!));
// Arrow keys move between tabs, as in a standard tab control.
document.querySelector('.tabs')!.addEventListener('keydown', (e) => {
    const key = (e as KeyboardEvent).key;
    if (key !== 'ArrowLeft' && key !== 'ArrowRight') return;
    const i = tabs.findIndex((t) => t.classList.contains('selected'));
    const next = tabs[(i + (key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length];
    selectTab(next.dataset.tab!);
    next.focus();
});
selectTab('general');

function screenSpace(): ScreenSpace {
    return screenSpaceRadios.find((r) => r.checked)?.value === 'moveWindows' ? 'moveWindows' : 'coverDock';
}

function theme(): Theme {
    return themeRadios.find((r) => r.checked)?.value === 'dark' ? 'dark' : 'light';
}

/** Shows the Options window in the taskbar's theme. */
function applyTheme(value: Theme) {
    document.documentElement.classList.toggle('dark', value === 'dark');
}

function current(): Preferences {
    return {
        hideHiddenApps: hideHiddenApps.checked,
        hideAppsWithoutWindows: hideAppsWithoutWindows.checked,
        barHeight: height,
        screenSpace: screenSpace(),
        separateWindows: separateWindows.checked,
        excludedApps: excludedApps.ids(),
        quickLaunch: quickLaunch.ids(),
        menuApps: menuApps.ids(),
        menuFolders: menuFolders.ids(),
        theme: theme(),
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
    for (const radio of themeRadios) radio.checked = radio.value === msg.preferences.theme;
    applyTheme(msg.preferences.theme);
    accessibilityTrusted = msg.accessibilityTrusted;
    dockHeight = msg.dockHeight;
    min = msg.barHeightMin;
    max = msg.barHeightMax;
    height = msg.preferences.barHeight;
    barHeight.min = String(min);
    barHeight.max = String(max);
    // Don't overwrite the box while the user is typing in it.
    if (document.activeElement !== barHeight) barHeight.value = String(height);
    excludedApps.set(msg.excludedAppDetails.map(fromApp));
    quickLaunch.set(msg.quickLaunchDetails.map(fromApp));
    menuApps.set(msg.menuAppDetails.map(fromApp));
    menuFolders.set(msg.menuFolderDetails.map(fromFolder));
    updateNotes();
});

for (const input of [hideHiddenApps, hideAppsWithoutWindows, separateWindows, ...screenSpaceRadios, ...themeRadios]) {
    input.addEventListener('change', () => {
        applyTheme(theme());
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
