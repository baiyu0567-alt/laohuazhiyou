/* ═══════════════════════════════════════════
   PresbyFriend — Main App Logic v0.1
   (老花之友 / PresbyFriend)
   ═══════════════════════════════════════════ */

// ─── i18n: Translations ───
const I18N = {
  en: {
    appName: 'PresbyFriend',
    subtitle: 'Read clearly without reading glasses',
    pasteRead: 'Paste & Read',
    pasteDesc: 'Paste text or a URL and read in large, clear font',
    cameraRead: 'Snap & Read',
    cameraDesc: 'Snap a photo of medicine labels, menus, fine print',
    settings: 'Settings',
    settingsDesc: 'Adjust font, contrast, theme for comfortable reading',
    footer: 'v0.1 · Data stored locally only',
    readerTitle: 'Reading Mode',
    back: '← Back',
    pasteHere: 'Paste text here, or enter a webpage URL...',
    startReading: 'Start Reading',
    warningPaste: '⚠️ Please paste text or a link first',
    loadingUrl: 'Loading page content...',
    extractFail: 'Could not extract enough content. Try pasting text directly.',
    loadFail: 'Failed to load: ',
    fontSize: 'Font Size',
    theme: 'Theme',
    light: 'White',
    sepia: 'Warm',
    dark: 'Dark',
    yellowBg: 'Yellow',
    lineHeight: 'Line Space',
    letterSpacing: 'Letter Space',
    cameraTitle: 'Snap & Read',
    magnifierHint: 'Point camera at small text — slide to zoom',
    zoom: 'Zoom',
    flashlight: '🔦 Flashlight',
    settingsTitle: 'Settings',
    distanceCal: '👁️ Reading Distance',
    distanceDesc: 'Hold your phone at your most comfortable reading distance, then calibrate.',
    calibrate: '📏 Calibrate',
    distanceResult: '✅ Calibrated! Recommended distance: ~',
    distanceCm: 'cm',
    defaultFont: '📏 Default Font Size',
    defaultTheme: '🎨 Default Theme',
    readingRuler: '📦 Reading Ruler',
    rulerDesc: 'Highlight current line to reduce skipping',
    dataMgmt: '💾 Data Management',
    clearData: 'Clear All Local Data',
    clearConfirm: 'Clear all local data? This will reset all settings.',
    dataCleared: 'Settings reset.',
    langSwitch: '🌐 Language',
    calibrating: '📏 Hold your phone at your most comfortable reading distance...',
    three: '3',
    two: '2',
    one: '1',
  },
  zh: {
    appName: '老花之友',
    subtitle: '不戴眼镜也能看清',
    pasteRead: '粘贴阅读',
    pasteDesc: '粘贴文字或链接，立即用大字号舒适阅读',
    cameraRead: '拍照阅读',
    cameraDesc: '拍药瓶、菜单、说明书，放大给你看',
    settings: '阅读设置',
    settingsDesc: '调节字体、对比度、色温，找到最舒服的阅读方式',
    footer: 'v0.1 · 数据仅保存在本设备',
    readerTitle: '阅读模式',
    back: '← 返回',
    pasteHere: '在此粘贴文字，或输入网页链接...',
    startReading: '开始阅读',
    warningPaste: '⚠️ 请先粘贴文字或链接',
    loadingUrl: '正在加载网页内容...',
    extractFail: '未能提取到足够的内容。请尝试直接粘贴文字。',
    loadFail: '加载失败: ',
    fontSize: '字号',
    theme: '主题',
    light: '白',
    sepia: '暖',
    dark: '暗',
    yellowBg: '黄底',
    lineHeight: '行距',
    letterSpacing: '字间距',
    cameraTitle: '拍照阅读',
    magnifierHint: '将摄像头对准小字 — 滑动变焦放大',
    zoom: '变焦',
    flashlight: '🔦 手电筒',
    settingsTitle: '阅读设置',
    distanceCal: '👁️ 阅读距离校准',
    distanceDesc: '把手机放到你平时看书最舒服的距离，然后点校准。',
    calibrate: '📏 开始校准',
    distanceResult: '✅ 已校准！推荐阅读距离: ~',
    distanceCm: '厘米',
    defaultFont: '📏 默认字号',
    defaultTheme: '🎨 默认主题',
    readingRuler: '📦 阅读标尺',
    rulerDesc: '高亮当前行，减少跳行',
    dataMgmt: '💾 数据管理',
    clearData: '清除所有本地数据',
    clearConfirm: '确定清除所有本地数据？这将重置所有设置。',
    dataCleared: '设置已重置。',
    langSwitch: '🌐 语言',
    calibrating: '📏 请将手机放到你平时阅读最舒服的距离...',
    three: '3',
    two: '2',
    one: '1',
  }
};

// ─── i18n: Translation Engine ───
let currentLang = 'en';  // default to English for Reddit audience

function t(key) {
  return I18N[currentLang]?.[key] ?? I18N.en[key] ?? key;
}

function setLanguage(lang) {
  currentLang = lang;
  localStorage.setItem('presbyfriend_lang', lang);
  renderUI();
}

function toggleLanguage() {
  setLanguage(currentLang === 'en' ? 'zh' : 'en');
}

// ─── Re-render all UI text ───
function renderUI() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.dataset.i18n;
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      el.placeholder = t(key);
    } else {
      el.textContent = t(key);
    }
  });

  // Update document lang
  document.documentElement.lang = currentLang === 'en' ? 'en' : 'zh-CN';
  document.title = t('appName') + ' — ' + (currentLang === 'en' ? 'Large Text Reading Assistant' : '大字号阅读助手');

  // Update lang toggle button text
  document.querySelectorAll('.lang-toggle').forEach(btn => {
    btn.textContent = currentLang === 'en' ? '中文' : 'English';
  });
}

// ─── Config ───
const DEFAULTS = {
  fontSize: 28,
  theme: 'dark',
  lineHeight: 1.8,
  letterSpacing: 1,
  readingDistance: null,
  rulerEnabled: false,
};

// ─── State ───
let state = loadSettings();
let cameraStream = null;

// ─── Init ───
document.addEventListener('DOMContentLoaded', () => {
  // Load language preference
  const savedLang = localStorage.getItem('presbyfriend_lang');
  if (savedLang) currentLang = savedLang;
  // Check browser language (only if no saved preference)
  else if (navigator.language && navigator.language.startsWith('zh')) currentLang = 'zh';

  applyTheme(state.theme);
  document.getElementById('setting-fontsize').value = state.fontSize;
  document.getElementById('setting-ruler').checked = state.rulerEnabled;
  renderUI();
  registerSW();
});

// ═══ View Switching ═══

function showView(view) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  const el = document.getElementById(`view-${view}`);
  if (el) {
    el.classList.add('active');
    window.scrollTo(0, 0);
  }
  applyTheme(state.theme, false);
  renderUI();
  if (view === 'camera') startCamera();
  if (view === 'home') stopCamera();
}

// ═══ Theme Management ═══

function applyTheme(theme, save = true) {
  document.documentElement.setAttribute('data-theme', theme);
  if (save) { state.theme = theme; saveSettings(); }
  document.querySelectorAll('.theme-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.theme === theme);
  });
}

function setTheme(theme) { applyTheme(theme); }
function setDefaultTheme(theme) { applyTheme(theme); state.theme = theme; saveSettings(); }

// ═══ Reader Core ═══

let currentFontSize = state.fontSize;
let currentLineHeight = state.lineHeight;
let currentLetterSpacing = state.letterSpacing;

function updateDisplayValues() {
  document.querySelectorAll('.fs-display').forEach(el => el.textContent = `${currentFontSize}px`);
  document.querySelectorAll('.lh-display').forEach(el => el.textContent = currentLineHeight.toFixed(1));
  document.querySelectorAll('.ls-display').forEach(el => el.textContent = `${currentLetterSpacing.toFixed(1)}px`);
}

function startReading() {
  const textarea = document.getElementById('reader-textarea');
  const raw = textarea.value.trim();
  if (!raw) {
    textarea.placeholder = t('warningPaste');
    return;
  }

  if (raw.match(/^https?:\/\//)) {
    fetchUrlContent(raw);
    return;
  }
  showReaderContent(raw);
}

async function fetchUrlContent(url) {
  const display = document.getElementById('reader-display');
  const content = document.getElementById('reader-content');
  display.classList.remove('hidden');
  content.textContent = t('loadingUrl');

  const extractText = (html) => {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, 'text/html');
    doc.querySelectorAll('script, style, nav, footer, header').forEach(el => el.remove());
    const text = (doc.body || doc).textContent.replace(/\s+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
    return text;
  };

  const proxies = [
    async () => {
      const resp = await fetch(url);
      return extractText(await resp.text());
    },
    async () => {
      const resp = await fetch(`https://api.allorigins.win/raw?url=${encodeURIComponent(url)}`);
      return extractText(await resp.text());
    },
  ];

  for (const tryFetch of proxies) {
    try {
      const text = await tryFetch();
      if (text.length > 50) { showReaderContent(text); return; }
    } catch {}
  }
  content.textContent = t('extractFail');
}

function showReaderContent(text) {
  document.getElementById('reader-input-area').classList.add('hidden');
  document.getElementById('reader-display').classList.remove('hidden');
  document.getElementById('reader-controls').classList.remove('hidden');
  currentFontSize = state.fontSize;
  currentLineHeight = state.lineHeight;
  currentLetterSpacing = state.letterSpacing;
  document.getElementById('reader-content').textContent = text;
  applyReaderStyles();
  updateDisplayValues();
  renderUI();
}

function applyReaderStyles() {
  const el = document.getElementById('reader-content');
  el.style.fontSize = `${currentFontSize}px`;
  el.style.setProperty('--lh', currentLineHeight);
  el.style.setProperty('--ls', `${currentLetterSpacing}px`);
}

function adjustFontSize(delta) {
  currentFontSize = Math.max(18, Math.min(96, currentFontSize + delta * 4));
  state.fontSize = currentFontSize; saveSettings();
  applyReaderStyles(); updateDisplayValues();
}

function adjustLineHeight(delta) {
  currentLineHeight = Math.max(1.0, Math.min(3.0, +(currentLineHeight + delta).toFixed(1)));
  state.lineHeight = currentLineHeight; saveSettings();
  applyReaderStyles(); updateDisplayValues();
}

function adjustLetterSpacing(delta) {
  currentLetterSpacing = Math.max(0, Math.min(5, +(currentLetterSpacing + delta).toFixed(1)));
  state.letterSpacing = currentLetterSpacing; saveSettings();
  applyReaderStyles(); updateDisplayValues();
}

function toggleControls() {
  document.getElementById('reader-controls').classList.toggle('hidden');
}

// ═══ Reading Ruler ═══

let rulerEl = null;

function toggleRuler() {
  state.rulerEnabled = document.getElementById('setting-ruler').checked;
  saveSettings();
  state.rulerEnabled ? enableRuler() : disableRuler();
}

function enableRuler() {
  if (rulerEl) return;
  rulerEl = document.createElement('div');
  rulerEl.className = 'reader-ruler';
  document.body.appendChild(rulerEl);
  const update = (e) => {
    const y = e.touches ? e.touches[0].clientY : e.clientY;
    rulerEl.style.top = `${y - 30}px`;
  };
  document.addEventListener('mousemove', update);
  document.addEventListener('touchmove', update);
  rulerEl._cleanup = () => {
    document.removeEventListener('mousemove', update);
    document.removeEventListener('touchmove', update);
  };
}

function disableRuler() {
  if (rulerEl) {
    if (rulerEl._cleanup) rulerEl._cleanup();
    rulerEl.remove(); rulerEl = null;
  }
}

// ═══ Settings ═══

function loadSettings() {
  try {
    const saved = localStorage.getItem('presbyfriend_settings');
    return saved ? { ...DEFAULTS, ...JSON.parse(saved) } : { ...DEFAULTS };
  } catch { return { ...DEFAULTS }; }
}

function saveSettings() {
  try { localStorage.setItem('presbyfriend_settings', JSON.stringify(state)); }
  catch (e) { console.warn('Save failed:', e); }
}

function updateSettingDisplay() {
  const val = document.getElementById('setting-fontsize').value;
  document.querySelectorAll('.setting-fs-display').forEach(el => el.textContent = `${val}px`);
  state.fontSize = parseInt(val); saveSettings();
}

function clearAllData() {
  if (confirm(t('clearConfirm'))) {
    localStorage.removeItem('presbyfriend_settings');
    localStorage.removeItem('presbyfriend_lang');
    state = { ...DEFAULTS };
    applyTheme(state.theme);
    document.getElementById('setting-fontsize').value = state.fontSize;
    document.querySelectorAll('.setting-fs-display').forEach(el => el.textContent = `${state.fontSize}px`);
    document.getElementById('setting-ruler').checked = false;
    disableRuler();
    alert(t('dataCleared'));
    renderUI();
  }
}

function calibrateDistance() {
  const result = document.getElementById('distance-result');
  result.classList.remove('hidden');
  const steps = ['three', 'two', 'one'];
  let count = 3;
  const tick = () => {
    if (count > 0) {
      result.textContent = t('calibrating') + ' ' + t(steps[3 - count]);
      count--;
      setTimeout(tick, 1000);
    } else {
      state.readingDistance = 35;
      saveSettings();
      result.textContent = t('distanceResult') + `35${t('distanceCm')}`;
    }
  };
  tick();
}

// ═══ Camera Magnifier ═══

let flashlightOn = false;

async function startCamera() {
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } }
    });
    document.getElementById('camera-preview').srcObject = cameraStream;
  } catch (e) {
    alert('Camera error: ' + e.message);
  }
}

function stopCamera() {
  if (cameraStream) { cameraStream.getTracks().forEach(t => t.stop()); cameraStream = null; }
  flashlightOn = false;
}

function setZoom(val) {
  const video = document.getElementById('camera-preview');
  video.style.transform = `scale(${val})`;
  document.querySelector('.zoom-value').textContent = `${parseFloat(val).toFixed(1)}x`;
}

async function toggleFlashlight() {
  if (!cameraStream) return;
  const track = cameraStream.getVideoTracks()[0];
  if (!track) return;
  try {
    flashlightOn = !flashlightOn;
    await track.applyConstraints({ advanced: [{ torch: flashlightOn }] });
    document.getElementById('flashlight-btn').classList.toggle('active', flashlightOn);
  } catch {
    flashlightOn = !flashlightOn;
  }
}

// ═══ PWA: SW ═══

async function registerSW() {
  if ('serviceWorker' in navigator) {
    try { await navigator.serviceWorker.register('sw.js'); }
    catch (e) { console.warn('SW failed:', e); }
  }
}

// ═══ Expose Globals ═══
Object.assign(window, {
  showView, setTheme, setDefaultTheme, startReading,
  adjustFontSize, adjustLineHeight, adjustLetterSpacing,
  toggleControls, calibrateDistance,
  toggleRuler, updateSettingDisplay, clearAllData,
  stopCamera, toggleLanguage, setZoom, toggleFlashlight,
});
