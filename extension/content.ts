let lastScroll = 0,
  lastSelection = 0;
function send(message: object) {
  // The trusted worker applies the URL policy before persistence or HTTP.
  // Content scripts cannot access storage.local, including the collector token.
  if (document.visibilityState === 'visible') chrome.runtime.sendMessage(message).catch(() => {});
}
document.addEventListener(
  'scroll',
  () => {
    if (Date.now() - lastScroll < 1000) return;
    lastScroll = Date.now();
    const height = document.documentElement.scrollHeight - innerHeight;
    send({ kind: 'scroll', scroll: height > 0 ? scrollY / height : 0 });
  },
  { passive: true },
);
document.addEventListener('selectionchange', () => {
  if (Date.now() - lastSelection < 1000) return;
  lastSelection = Date.now();
  const length = window.getSelection()?.toString().length ?? 0;
  if (length > 40) send({ kind: 'select', length });
});
document.addEventListener('copy', () =>
  send({ kind: 'copy', length: window.getSelection()?.toString().length ?? 0 }),
);
