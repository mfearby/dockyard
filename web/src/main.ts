export {};
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
  const baseLeft = el.offsetLeft;
  const startX = e.clientX;
  let moved = false;
  let to = from;
  el.setPointerCapture(e.pointerId);

  const onMove = (ev: PointerEvent) => {
    const dx = ev.clientX - startX;
    if (!moved && Math.abs(dx) < 5) return;
    moved = dragging = true;
    el.classList.add('dragging');
    const minDx = -from * step;
    const maxDx = (items.length - 1 - from) * step;
    const clamped = Math.max(minDx, Math.min(maxDx, dx));
    el.style.transform = `translateX(${clamped}px)`;
    to = Math.max(0, Math.min(items.length - 1, Math.round((baseLeft + clamped) / step)));
    items.forEach((it, j) => {
      if (it === el) return;
      const shift = from < to && j > from && j <= to ? -step
                  : from > to && j >= to && j < from ? step : 0;
      it.style.transform = shift ? `translateX(${shift}px)` : '';
    });
  };

  const onUp = () => {
    el.removeEventListener('pointermove', onMove);
    el.removeEventListener('pointerup', onUp);
    el.removeEventListener('pointercancel', onUp);
    dragging = false;
    if (moved) {
      const [a] = apps.splice(from, 1);
      apps.splice(to, 0, a);
      send({ type: 'setOrder', order: apps.map((x) => x.bundleId) });
    } else {
      send({ type: 'activate', bundleId: el.dataset.id });
    }
    if (pending) { apps = pending; pending = null; }
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
