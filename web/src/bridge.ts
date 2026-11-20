// Message types shared with the Swift host. Field names must match DockyardCore/Bridge.swift.

export interface AppInfo {
    /** Unique per button: the bundle ID for an app button, or "bundleId#serial" for a window button. */
    id: string;
    bundleId: string;
    /** Button label: the app name or window title. */
    name: string;
    /** Tooltip text. */
    title: string;
    /** The app's Dock badge, such as an unread count. Absent when there's none. */
    badge?: string;
    icon: string;
    active: boolean;
}

/**
 * How the taskbar avoids covering windows:
 * - coverDock: the Dock stays visible at the bottom, so macOS keeps windows above it, and the bar covers it.
 * - moveWindows: Dockyard moves and resizes windows so they stay above the bar.
 */
export type ScreenSpace = 'coverDock' | 'moveWindows';

export type Theme = 'light' | 'dark';

/** The Options window's app lists, managed with Add… and Remove. */
export type AppList = 'excludedApps' | 'quickLaunch';

export interface Preferences {
    hideHiddenApps: boolean;
    hideAppsWithoutWindows: boolean;
    /** Bar height in points. */
    barHeight: number;
    screenSpace: ScreenSpace;
    /** One button per window instead of per app. */
    separateWindows: boolean;
    /** Bundle IDs of apps that never get a button. */
    excludedApps: string[];
    /** Bundle IDs of the Quick Launch icons, left to right. */
    quickLaunch: string[];
    theme: Theme;
}

/** An app's name and icon, for apps that may not be running. */
export interface AppSummary {
    bundleId: string;
    name: string;
    icon: string;
}

/** Messages from Swift to the page. */
export type NativeMsg =
    | { type: 'state'; apps: AppInfo[]; collapsed: boolean; theme: Theme; quickLaunch: AppSummary[] }
    | {
          type: 'settings';
          preferences: Preferences;
          accessibilityTrusted: boolean;
          /** Space the Dock reserves at the bottom of the screen, or 0. */
          dockHeight: number;
          /** Name and icon for each of `preferences.excludedApps`, in the same order. */
          excludedAppDetails: AppSummary[];
          /** Name and icon for each of `preferences.quickLaunch`, in the same order. */
          quickLaunchDetails: AppSummary[];
          barHeightMin: number;
          barHeightMax: number;
      };

/** Messages from the page to Swift. */
export type UIMsg =
    | { type: 'ready' }
    | { type: 'menu' }
    | { type: 'activate'; id: string }
    /** `order` lists button IDs left to right. */
    | { type: 'setOrder'; order: string[] }
    | { type: 'setCollapsed'; collapsed: boolean }
    | { type: 'launch'; bundleId: string }
    /** Elements that show a tooltip on hover; positions in CSS px (points) from the bar's left edge. */
    | { type: 'setTooltips'; tooltips: { id: string; text: string; left: number; width: number }[] }
    | { type: 'getSettings' }
    | { type: 'setPreferences'; preferences: Preferences }
    | { type: 'requestAccessibility' }
    | { type: 'chooseApp'; list: AppList }
    | { type: 'resizeSettings'; height: number }
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
