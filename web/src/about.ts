import { onNative, send, type AboutLink } from './bridge.ts';

onNative((msg) => {
    if (msg.type !== 'about') return;
    document.getElementById('version')!.textContent = msg.version;
    document.documentElement.classList.toggle('dark', msg.theme === 'dark');
});

// Links open in the browser, not in this window. The page only names the link; Swift has the URLs.
for (const link of Array.from(document.querySelectorAll<HTMLAnchorElement>('a[data-link]'))) {
    link.addEventListener('click', (e) => {
        e.preventDefault();
        send({ type: 'openLink', link: link.dataset.link as AboutLink });
    });
}

const close = () => send({ type: 'closeSettings' });
document.getElementById('ok')!.addEventListener('click', close);

// The app has no menu bar, so handle the usual close shortcuts here.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || e.key === 'Enter' || (e.metaKey && e.key === 'w')) close();
});

// Size the window to the content.
new ResizeObserver(() => {
    send({ type: 'resizeSettings', height: Math.ceil(document.body.getBoundingClientRect().height) });
}).observe(document.body);

send({ type: 'getAbout' });
