export function installSoundSettings(sounds, hoverPlay) {
  const dialog = document.querySelector('#sound-settings');
  const toggle = document.querySelector('#sounds-enabled');
  const menuToggle = document.querySelector('#sound-toggle');
  const select = document.querySelector('#sound-set');
  const preview = document.querySelector('#sound-preview');
  const description = document.querySelector('#sound-description');
  const batToggle = document.querySelector('#bat-cursor');
  let opener;
  const descriptions = {
    fuzzy: 'Soft rustles and a little gulp.',
    rubber: 'Bouncy pops and playful squeaks.',
    arcade: 'Tiny electronic chirps and zaps.'
  };
  function update() {
    toggle.checked = sounds.enabled;
    select.value = sounds.set;
    preview.disabled = !sounds.enabled;
    menuToggle.setAttribute('aria-pressed', String(sounds.enabled));
    menuToggle.title = sounds.enabled ? 'Mute sound effects' : 'Unmute sound effects';
    menuToggle.setAttribute('aria-label', menuToggle.title);
    description.textContent = descriptions[sounds.set];
    batToggle.checked = hoverPlay.batCursor;
  }
  for (const button of document.querySelectorAll('[data-open-sound-settings]')) {
    button.addEventListener('click', () => {
      opener = button;
      hoverPlay.cancel();
      update();
      if (!dialog.open) dialog.showModal();
    });
  }
  function setEnabled(enabled) {
    sounds.setEnabled(enabled);
    if (enabled) sounds.unlock();
    update();
  }
  menuToggle.addEventListener('click', () => setEnabled(!sounds.enabled));
  batToggle.addEventListener('change', () => hoverPlay.setBatCursor(batToggle.checked));
  toggle.addEventListener('change', () => setEnabled(toggle.checked));
  select.addEventListener('change', () => { sounds.selectSet(select.value); update(); });
  preview.addEventListener('click', () => {
    sounds.unlock();
    void sounds.play('window', {preview: true});
  });
  document.querySelector('#close-sound-settings').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => {
    sounds.cancel('preview');
    opener?.focus({preventScroll: true});
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) sounds.stop(); });
  update();
}
