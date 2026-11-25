import { onNative, send, type AppInfo, type AppSummary } from './bridge.ts';
import { mix, textOn } from './colors.ts';
import { applyOrder, dragTarget, moveItem, shiftFor } from './reorder.ts';

const tasksEl = document.getElementById('tasks')!;
const toggleEl = document.getElementById('toggle')!;
const quickEl = document.getElementById('quick')!;
const GAP = 2;

let collapsed = false;

function setCollapsed(value: boolean) {
    collapsed = value;
    document.body.classList.toggle('collapsed', value);
    toggleEl.dataset.tip = value ? 'Show taskbar' : 'Hide taskbar';
    sendTooltips();
}

// Tooltip text lives in data-tip, not title: macOS never shows title tooltips for the bar (Dockyard isn't
// the active app), so Swift draws them instead, using the positions sent here.
function sendTooltips() {
    const els = Array.from(document.querySelectorAll<HTMLElement>('[data-tip]'));
    const tooltips = els.map((el, i) => {
        const r = el.getBoundingClientRect();
        return { id: el.dataset.id ?? el.id ?? String(i), text: el.dataset.tip ?? '', left: r.left, width: r.width };
    });
    // Stretch the first and last visible elements to the bar's ends, matching clickableAt, so hovering or
    // right-clicking in the very corners uses the menu button and the toggle.
    const visible = tooltips.filter((t) => t.width > 0).sort((a, b) => a.left - b.left);
    if (visible.length > 0) {
        const first = visible[0];
        first.width += first.left;
        first.left = 0;
        const last = visible[visible.length - 1];
        last.width = window.innerWidth - last.left;
    }
    send({ type: 'setTooltips', tooltips });
}

let apps: AppInfo[] = [];
let dragging = false;
let pending: AppInfo[] | null = null;

function render() {
    tasksEl.replaceChildren(...apps.map((a) => {
        const el = document.createElement('div');
        el.className = 'task' + (a.active ? ' active' : '') + (a.loading ? ' loading' : '');
        el.dataset.id = a.id;
        el.dataset.tip = a.title;
        if (a.color) {
            // A button without focus shows the app's colour at half strength (blended 50/50 with the theme's
            // normal button colour, as if 50% transparent), so it doesn't overpower the bar. The focused button
            // uses the full colour in place of the darker squares of its chequer. The label is black or white,
            // whichever reads better on what's behind it.
            const face = a.active ? a.color : (mix(a.color, themeColor('--face')) ?? a.color);
            const behind = a.active ? (mix(a.color, themeColor('--mesh-b')) ?? a.color) : face;
            el.style.setProperty('--face', face);
            el.style.setProperty('--mesh-a', a.color);
            el.style.color = textOn(behind);
        }
        const icon = document.createElement('span');
        icon.className = 'icon';
        const img = document.createElement('img');
        img.src = a.icon;
        icon.append(img);
        if (a.loading) icon.append(hourglass());
        if (a.badge) {
            const badge = document.createElement('span');
            badge.className = 'badge';
            badge.textContent = a.badge;
            icon.append(badge);
        }
        const label = document.createElement('span');
        label.className = 'label';
        label.textContent = a.name;
        el.append(icon, label);
        return el;
    }));
    sendTooltips();
}

/** Identifies the Quick Launch icons currently shown, so unchanged lists aren't redrawn every second. */
let quickKey = '';

function renderQuickLaunch(items: AppSummary[]) {
    const key = JSON.stringify(items.map((i) => [i.bundleId, i.name]));
    if (key === quickKey) return;
    quickKey = key;
    quickEl.replaceChildren(...items.map((item) => {
        const el = document.createElement('div');
        el.className = 'launcher';
        el.dataset.bundleId = item.bundleId;
        el.dataset.id = 'launch:' + item.bundleId;
        el.dataset.tip = item.name;
        const img = document.createElement('img');
        img.src = item.icon;
        el.append(img);
        return el;
    }));
    sendTooltips();
}

/**
 * The clickable element in the bar's column at `x`: the menu button, a Quick Launch icon, a taskbar button or the
 * toggle. The bar is a single row, so only x matters, and a click in the margin above or below a button counts
 * as a click on it. Clicks beyond the first or last element (the bar's corners) count for that element, so
 * throwing the pointer into a bottom corner hits the menu button or the toggle. Hidden elements (e.g. while the
 * bar is retracted) have no width and are skipped.
 */
function clickableAt(x: number): HTMLElement | null {
    const els = Array.from(document.querySelectorAll<HTMLElement>('#start, .launcher, .task, #toggle'))
        .map((el) => ({ el, r: el.getBoundingClientRect() }))
        .filter(({ r }) => r.width > 0);
    if (els.length === 0) return null;
    const hit = els.find(({ r }) => x >= r.left && x < r.right);
    if (hit) return hit.el;
    if (x < els[0].r.left) return els[0].el;
    if (x >= els[els.length - 1].r.right) return els[els.length - 1].el;
    return null;
}

/** The element pressed, so a click only counts if it's released over the same one; drawn pressed meanwhile. */
let pressed: HTMLElement | null = null;

function release() {
    pressed?.classList.remove('pressed');
    pressed = null;
}

/** A small hourglass shown over a starting app's icon. Symmetrical, so its half-turn animation loops smoothly. */
function hourglass(): HTMLElement {
    const el = document.createElement('span');
    el.className = 'hourglass';
    el.innerHTML = '<svg viewBox="0 0 10 14" width="10" height="14" aria-hidden="true">'
        + '<rect x="0.5" y="0.5" width="9" height="1.5" fill="#000"/>'
        + '<rect x="0.5" y="12" width="9" height="1.5" fill="#000"/>'
        + '<path d="M1.5 2 H8.5 L5.6 7 L8.5 12 H1.5 L4.4 7 Z" fill="#fff" stroke="#000" stroke-width="0.8"/>'
        + '<path d="M3 3.2 H7 L5 6 Z M3 10.8 H7 L5 8 Z" fill="#c9971c"/>'
        + '</svg>';
    return el;
}

/** One of the current theme's colours, e.g. '--face' (the normal button colour) or '--mesh-b' (the lighter
 *  squares of the focused button's chequer). Read from the body, so per-button overrides don't affect it. */
function themeColor(name: string): string {
    return getComputedStyle(document.body).getPropertyValue(name).trim();
}

// Buttons shrink and grow with the window, e.g. when the bar is retracted or the screen changes.
new ResizeObserver(sendTooltips).observe(tasksEl);

onNative((msg) => {
    if (msg.type !== 'state') return;
    document.body.classList.toggle('dark', msg.theme === 'dark');
    setCollapsed(msg.collapsed);
    renderQuickLaunch(msg.quickLaunch);
    if (dragging) { pending = msg.apps; return; }
    apps = msg.apps;
    render();
});

document.addEventListener('pointerdown', (e) => {
    // Control-click is a right-click on macOS, handled natively.
    if (e.button !== 0 || e.ctrlKey) return;
    const el = clickableAt(e.clientX);
    if (!el) return;
    release();
    pressed = el;
    if (el.classList.contains('task')) {
        startTaskPress(el, e);
    } else {
        el.classList.add('pressed');
    }
});

document.addEventListener('pointerup', () => {
    if (pressed && !pressed.classList.contains('task')) pressed.classList.remove('pressed');
});
document.addEventListener('pointercancel', release);

// The menu button, Quick Launch icons and the toggle act on click; taskbar buttons act in startTaskPress.
document.addEventListener('click', (e) => {
    const el = clickableAt(e.clientX);
    const wasPressed = pressed;
    release();
    if (!el || el !== wasPressed || el.classList.contains('task')) return;
    if (el.id === 'start') {
        send({ type: 'menu' });
    } else if (el.id === 'toggle') {
        toggleCollapsed();
    } else if (el.dataset.bundleId) {
        send({ type: 'launch', bundleId: el.dataset.bundleId });
    }
});

// Pointer-based drag to reorder a taskbar button. A press that moves < 5px counts as a click.
function startTaskPress(el: HTMLElement, e: PointerEvent) {
    const items = Array.from(tasksEl.children) as HTMLElement[];
    const from = items.indexOf(el);
    const step = el.offsetWidth + GAP;
    const startX = e.clientX;
    let moved = false;
    let to = from;
    el.setPointerCapture(e.pointerId);

    const onMove = (ev: PointerEvent) => {
        const dx = ev.clientX - startX;
        if (!moved && Math.abs(dx) < 5) return;
        moved = dragging = true;
        el.classList.add('dragging');
        const target = dragTarget(from, dx, step, items.length);
        to = target.to;
        el.style.transform = `translateX(${target.offset}px)`;
        items.forEach((it, j) => {
            if (it === el) return;
            const shift = shiftFor(j, from, to, step);
            it.style.transform = shift ? `translateX(${shift}px)` : '';
        });
    };

    const onUp = () => {
        el.removeEventListener('pointermove', onMove);
        el.removeEventListener('pointerup', onUp);
        el.removeEventListener('pointercancel', onUp);
        dragging = false;
        if (moved) {
            apps = moveItem(apps, from, to);
            const order = apps.map((x) => x.id);
            // An update that arrived mid-drag was sorted by the old order; re-sort it by the new one.
            if (pending) { apps = applyOrder(pending, order); pending = null; }
            send({ type: 'setOrder', order });
        } else {
            send({ type: 'activate', id: el.dataset.id! });
            if (pending) { apps = pending; pending = null; }
        }
        render();
    };

    el.addEventListener('pointermove', onMove);
    el.addEventListener('pointerup', onUp);
    el.addEventListener('pointercancel', onUp);
}

// Right-clicks are handled natively (BarWebView in main.swift), which shows Dockyard's own menus.
document.addEventListener('contextmenu', (e) => e.preventDefault());

function toggleCollapsed() {
    // When retracting, hide the buttons before Swift shrinks the window, so the narrow strip never
    // shows a sliver of the menu button. When expanding, wait for Swift to widen the window first;
    // the state message it sends back removes the class.
    const next = !collapsed;
    if (next) setCollapsed(true);
    send({ type: 'setCollapsed', collapsed: next });
}

send({ type: 'ready' });
