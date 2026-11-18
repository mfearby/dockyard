// Message types shared with the Swift host. Field names must match DockyardCore/Bridge.swift.

export interface AppInfo {
    bundleId: string;
    name: string;
    icon: string;
    active: boolean;
}

export interface Preferences {
    hideHiddenApps: boolean;
    hideAppsWithoutWindows: boolean;
    /** Bar height in points. */
    barHeight: number;
}

/** Messages from Swift to the page. */
export type NativeMsg =
    | { type: 'state'; apps: AppInfo[]; collapsed: boolean }
    | {
          type: 'settings';
          preferences: Preferences;
          accessibilityTrusted: boolean;
          /** Space the Dock reserves at the bottom of the screen, or 0. */
          dockHeight: number;
          barHeightMin: number;
          barHeightMax: number;
      };

/** Messages from the page to Swift. */
export type UIMsg =
    | { type: 'ready' }
    | { type: 'menu' }
    | { type: 'activate'; bundleId: string }
    | { type: 'setOrder'; order: string[] }
    | { type: 'setCollapsed'; collapsed: boolean }
    | { type: 'getSettings' }
    | { type: 'setPreferences'; preferences: Preferences }
    | { type: 'requestAccessibility' }
    | { type: 'closeSettings' };

declare global {
    interface Window {
        onNative?: (msg: NativeMsg) => void;
        webkit?: { messageHandlers: { native: { postMessage(m: UIMsg): void } } };
    }
}

export function send(msg: UIMsg): void {
    window.webkit?.messageHandlers.native.postMessage(msg);
}

export function onNative(handler: (msg: NativeMsg) => void): void {
    window.onNative = handler;
}
