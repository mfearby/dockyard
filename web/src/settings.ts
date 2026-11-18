import { onNative, send, type Preferences } from './bridge.ts';

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const hideHiddenApps = byId<HTMLInputElement>('hideHiddenApps');
const hideAppsWithoutWindows = byId<HTMLInputElement>('hideAppsWithoutWindows');
const axNote = byId<HTMLDivElement>('axNote');
let accessibilityTrusted = true;

function current(): Preferences {
    return {
        hideHiddenApps: hideHiddenApps.checked,
        hideAppsWithoutWindows: hideAppsWithoutWindows.checked,
    };
}

function updateNote() {
    axNote.hidden = accessibilityTrusted || !hideAppsWithoutWindows.checked;
}

onNative((msg) => {
    if (msg.type !== 'settings') return;
    hideHiddenApps.checked = msg.preferences.hideHiddenApps;
    hideAppsWithoutWindows.checked = msg.preferences.hideAppsWithoutWindows;
    accessibilityTrusted = msg.accessibilityTrusted;
    updateNote();
});

for (const box of [hideHiddenApps, hideAppsWithoutWindows]) {
    box.addEventListener('change', () => {
        updateNote();
        send({ type: 'setPreferences', preferences: current() });
    });
}

byId('grantAx').addEventListener('click', () => send({ type: 'requestAccessibility' }));
byId('close').addEventListener('click', () => send({ type: 'closeSettings' }));

// The app has no menu bar, so handle the usual close shortcuts here.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || (e.metaKey && e.key === 'w')) send({ type: 'closeSettings' });
});

send({ type: 'getSettings' });
