import { applyOrder, dragTarget, moveItem, shiftFor } from './reorder.ts';

interface AppInfo { bundleId: string; name: string; icon: string; active: boolean }
type NativeMsg = { type: 'state'; apps: AppInfo[] };

declare global {
  interface Window {
    onNative: (msg: NativeMsg) => void;
    webkit?: { messageHandlers: { native: { postMessage(m: unknown): void } } };
  }
}

const send = (m: unknown) => window.webkit?.messageHandlers.native.postMessage(m);
const tasksEl = document.getElementById('tasks')!;
const GAP = 2;

let apps: AppInfo[] = [];
let dragging = false;
let pending: AppInfo[] | null = null;

function render() {
  tasksEl.replaceChildren(...apps.map((a) => {
    const el = document.createElement('div');
    el.className = 'task' + (a.active ? ' active' : '');
    el.dataset.id = a.bundleId;
    el.title = a.name;
    const img = document.createElement('img');
    img.src = a.icon;
    const label = document.createElement('span');
    label.textContent = a.name;
    el.append(img, label);
    return el;
  }));
}

window.onNative = (msg) => {
  if (msg.type !== 'state') return;
  if (dragging) { pending = msg.apps; return; }
  apps = msg.apps;
  render();
};

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
      const order = apps.map((x) => x.bundleId);
      // An update that arrived mid-drag was sorted by the old order; re-sort it by the new one.
      if (pending) { apps = applyOrder(pending, order); pending = null; }
      send({ type: 'setOrder', order });
    } else {
      send({ type: 'activate', bundleId: el.dataset.id });
      if (pending) { apps = pending; pending = null; }
    }
    render();
  };

  el.addEventListener('pointermove', onMove);
  el.addEventListener('pointerup', onUp);
  el.addEventListener('pointercancel', onUp);
});

document.getElementById('start')!.addEventListener('click', () => send({ type: 'menu' }));

const clock = document.getElementById('clock')!;
const tick = () => { clock.textContent = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); };
tick();
setInterval(tick, 10_000);

send({ type: 'ready' });
