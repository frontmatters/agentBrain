/* Behavior only: theme changes never touch the wizard or the form contract. */
(() => {
  const root = document.documentElement;
  root.classList.add('js');
  const mode = document.getElementById('mode');
  const palette = document.getElementById('palette');
  const custom = document.getElementById('custom-accent');
  const settings = document.getElementById('settings');
  const hex = /^#[0-9a-fA-F]{6}$/;
  const modes = ['auto', 'light', 'dark'];
  const palettes = ['frontmatters', 'ocean', 'forest', 'mono', 'custom'];
  function ink(color) {
    const rgb = [1, 3, 5].map(i => parseInt(color.slice(i, i + 2), 16) / 255);
    const l = rgb.map(n => n <= .04045 ? n / 12.92 : ((n + .055) / 1.055) ** 2.4);
    const luminance = .2126 * l[0] + .7152 * l[1] + .0722 * l[2];
    return luminance > .18 ? 'oklch(0 0 0)' : 'oklch(1 0 0)';
  }
  function applyTheme() {
    root.dataset.mode = mode.value;
    root.dataset.palette = palette.value;
    custom.hidden = palette.value !== 'custom';
    if (palette.value === 'custom' && hex.test(custom.value)) {
      root.style.setProperty('--user-accent', custom.value);
      root.style.setProperty('--user-ink', ink(custom.value));
    } else {
      root.style.removeProperty('--user-accent');
      root.style.removeProperty('--user-ink');
    }
    try { localStorage.setItem('agentbrain-onboard-theme', JSON.stringify({ mode: mode.value, palette: palette.value, color: custom.value })); } catch (_) { /* Storage can be unavailable. */ }
  }
  try {
    const saved = JSON.parse(localStorage.getItem('agentbrain-onboard-theme'));
    if (saved && modes.includes(saved.mode) && palettes.includes(saved.palette)) {
      mode.value = saved.mode;
      palette.value = saved.palette;
      if (typeof saved.color === 'string' && hex.test(saved.color)) custom.value = saved.color;
    }
  } catch (_) { /* Invalid or unavailable storage: use system defaults. */ }
  [mode, palette, custom].forEach(control => control.addEventListener('change', applyTheme));
  custom.addEventListener('input', applyTheme);
  applyTheme();
  settings.addEventListener('keydown', event => { if (event.key === 'Escape') { settings.open = false; settings.querySelector('summary').focus(); } });

  for (const name of fields) {
    const field = document.getElementById(name);
    if (!field) continue;
    const own = document.getElementById('custom-' + name);
    field.addEventListener('change', () => {
      own.classList.toggle('hidden', field.value !== '__custom__');
      if (field.value === '__custom__') own.focus();
    });
  }
  const language = document.getElementById('language');
  language.addEventListener('change', () => document.getElementById('group-artifactLanguage').classList.toggle('hidden', language.value === 'English'));
  language.dispatchEvent(new Event('change'));

  const steps = [...document.querySelectorAll('.step')];
  const markers = [...document.querySelectorAll('.steps li')];
  const prev = document.getElementById('previous');
  const next = document.getElementById('next');
  const save = document.getElementById('save');
  const status = document.getElementById('status');
  let index = 0;
  function show(step, focus) {
    index = step;
    steps.forEach((section, i) => { section.hidden = i !== index; });
    markers.forEach((marker, i) => { marker.classList.toggle('current', i === index); if (i === index) marker.setAttribute('aria-current', 'step'); else marker.removeAttribute('aria-current'); });
    prev.hidden = index === 0;
    next.hidden = index === steps.length - 1;
    save.hidden = index !== steps.length - 1;
    status.textContent = '';
    status.classList.remove('error');
    if (focus) { steps[index].querySelector('h2').focus(); window.scrollTo({ top: 0, behavior: 'instant' }); }
  }
  function values() {
    const result = {};
    for (const name of fields) {
      const own = document.getElementById('custom-' + name).value.trim();
      if (types[name] === 'multi') {
        result[name] = [...document.querySelectorAll('input[name="' + name + '"]:checked')].map(el => el.value);
        result[name].push(...own.split(',').map(x => x.trim()).filter(Boolean));
      } else {
        const selected = document.getElementById(name).value;
        result[name] = selected === '__custom__' ? own : selected;
      }
    }
    if (result.language === 'English') result.artifactLanguage = 'english-artifacts';
    return result;
  }
  function validStep() {
    const answers = values();
    for (const field of steps[index].querySelectorAll('fieldset')) {
      if (field.classList.contains('hidden')) continue;
      const name = field.id.slice(6);
      if (types[name] === 'multi' ? answers[name].length === 0 : !answers[name]) {
        status.textContent = 'Complete ' + field.querySelector('legend').textContent + ' to continue.';
        status.classList.add('error');
        const input = field.querySelector('select')?.value === '__custom__' ? field.querySelector('input[type=text]') : field.querySelector('select, input[type=checkbox], input[type=text]');
        input?.focus();
        return false;
      }
    }
    status.textContent = '';
    status.classList.remove('error');
    return true;
  }
  next.addEventListener('click', () => { if (validStep()) show(index + 1, true); });
  prev.addEventListener('click', () => show(index - 1, true));
  show(0, false);

  document.getElementById('onboard').addEventListener('submit', async event => {
    event.preventDefault();
    if (!validStep()) return;
    save.disabled = true;
    save.textContent = 'Saving...';
    status.textContent = 'Running the local terminal wizard...';
    try {
      const response = await fetch('/submit', { method: 'POST', headers: {
        'Content-Type': 'application/json', 'X-Onboard-Token': document.getElementById('token').value
      }, body: JSON.stringify(values()) });
      if (!response.ok) throw new Error('The wizard could not save these choices. Check the terminal and try again.');
      status.textContent = await response.text();
      status.classList.remove('error');
      save.textContent = 'Saved';
    } catch (error) {
      status.textContent = error.message || 'The local server did not respond. Try again.';
      status.classList.add('error');
      save.disabled = false;
      save.textContent = 'Save answers';
    }
  });
})();
