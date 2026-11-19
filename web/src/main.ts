import { onNative, send, type AppInfo } from './bridge.ts';
import { applyOrder, dragTarget, moveItem, shiftFor } from './reorder.ts';

const tasksEl = document.getElementById('tasks')!;
const toggleEl = document.getElementById('toggle')!;
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
    send({
        type: 'setTooltips',
        tooltips: els.map((el, i) => {
            const r = el.getBoundingClientRect();
            return { id: el.dataset.id ?? el.id ?? String(i), text: el.dataset.tip ?? '', left: r.left, width: r.width };
        }),
    });
}

let apps: AppInfo[] = [];
let dragging = false;
let pending: AppInfo[] | null = null;

function render() {
    tasksEl.replaceChildren(...apps.map((a) => {
        const el = document.createElement('div');
        el.className = 'task' + (a.active ? ' active' : '');
        el.dataset.id = a.id;
        el.dataset.tip = a.title;
        const icon = document.createElement('span');
        icon.className = 'icon';
        const img = document.createElement('img');
        img.src = a.icon;
        icon.append(img);
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

// Buttons shrink and grow with the window, e.g. when the bar is retracted or the screen changes.
new ResizeObserver(sendTooltips).observe(tasksEl);

onNative((msg) => {
    if (msg.type !== 'state') return;
    document.body.classList.toggle('dark', msg.theme === 'dark');
    setCollapsed(msg.collapsed);
    if (dragging) { pending = msg.apps; return; }
    apps = msg.apps;
    render();
});

// Pointer-based drag to reorder. A press that moves < 5px counts as a click.
tasksEl.addEventListener('pointerdown', (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>('.task');
    if (!el || e.button !== 0) return;
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
});

document.getElementById('start')!.addEventListener('click', () => send({ type: 'menu' }));

toggleEl.addEventListener('click', () => {
    // When retracting, hide the buttons before Swift shrinks the window, so the narrow strip never
    // shows a sliver of the menu button. When expanding, wait for Swift to widen the window first;
    // the state message it sends back removes the class.
    const next = !collapsed;
    if (next) setCollapsed(true);
    send({ type: 'setCollapsed', collapsed: next });
});

send({ type: 'ready' });
