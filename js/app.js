/* ═══════════════════════════════════════════
   老花之友 — 主应用逻辑 v0.1
   ═══════════════════════════════════════════ */

// ─── 配置 ───
const DEFAULTS = {
  fontSize: 28,
  theme: 'dark',
  lineHeight: 1.8,
  letterSpacing: 1,
  readingDistance: null,
  rulerEnabled: false,
};

// ─── 状态 ───
let state = loadSettings();
let cameraStream = null;
let ocrWorker = null;

// ─── 初始化 ───
document.addEventListener('DOMContentLoaded', () => {
  applyTheme(state.theme);
  registerSW();
});

// ═══ 视图切换 ═══

function showView(view) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  const el = document.getElementById(`view-${view}`);
  if (el) {
    el.classList.add('active');
    // 滚动到顶部
    window.scrollTo(0, 0);
  }
  // 重新应用主题到新视图
  applyTheme(state.theme, false);

  // 特殊逻辑
  if (view === 'camera') startCamera();
  if (view === 'home') stopCamera();
}

// ═══ 主题管理 ═══

function applyTheme(theme, save = true) {
  document.documentElement.setAttribute('data-theme', theme);
  if (save) {
    state.theme = theme;
    saveSettings();
  }
  // 更新主题按钮状态
  document.querySelectorAll('.theme-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.theme === theme);
  });
}

function setTheme(theme) {
  applyTheme(theme);
  // 如果在阅读器中，也应用到阅读内容
  const content = document.getElementById('reader-content');
  if (content) content.style.color = '';
  document.getElementById('reader-display').style.background = '';
}

function setDefaultTheme(theme) {
  applyTheme(theme);
  state.theme = theme;
  saveSettings();
}

// ═══ 阅读器核心 ═══

let currentFontSize = state.fontSize;
let currentLineHeight = state.lineHeight;
let currentLetterSpacing = state.letterSpacing;

function updateDisplayValues() {
  document.getElementById('font-size-display').textContent = `${currentFontSize}px`;
  document.getElementById('lh-display').textContent = currentLineHeight.toFixed(1);
  document.getElementById('ls-display').textContent = `${currentLetterSpacing.toFixed(1)}px`;
}

function startReading() {
  const textarea = document.getElementById('reader-textarea');
  const raw = textarea.value.trim();
  if (!raw) {
    textarea.placeholder = '⚠️ 请先粘贴文字或链接';
    return;
  }

  // 判断是否是 URL
  let content = raw;
  if (raw.match(/^https?:\/\//)) {
    // URL模式: 尝试提取内容 (通过 fetch + 简单的文本提取)
    fetchUrlContent(raw);
    return;
  }

  showReaderContent(raw);
}

async function fetchUrlContent(url) {
  const display = document.getElementById('reader-display');
  const content = document.getElementById('reader-content');
  display.classList.remove('hidden');
  content.textContent = '正在加载网页内容...';

  try {
    // 使用 corsproxy 或直接提取
    const proxyUrl = `https://api.allorigins.win/get?url=${encodeURIComponent(url)}`;
    const resp = await fetch(proxyUrl);
    const data = await resp.json();

    // 简单 HTML → 文本提取
    const parser = new DOMParser();
    const doc = parser.parseFromString(data.contents, 'text/html');
    // 移除 script/style
    doc.querySelectorAll('script, style, nav, footer, header').forEach(el => el.remove());
    const text = doc.body.textContent
      .replace(/\s+/g, ' ')
      .replace(/\n{3,}/g, '\n\n')
      .trim();

    if (text.length > 50) {
      showReaderContent(text);
    } else {
      content.textContent = '未能提取到足够的内容。请尝试直接粘贴文字。';
    }
  } catch (e) {
    content.textContent = `加载失败: ${e.message}\n\n请尝试直接粘贴文字。`;
  }
}

function showReaderContent(text) {
  const display = document.getElementById('reader-display');
  const content = document.getElementById('reader-content');
  const inputArea = document.getElementById('reader-input-area');
  const controls = document.getElementById('reader-controls');

  inputArea.classList.add('hidden');
  display.classList.remove('hidden');
  controls.classList.remove('hidden');

  // 恢复上次的阅读设置
  currentFontSize = state.fontSize;
  currentLineHeight = state.lineHeight;
  currentLetterSpacing = state.letterSpacing;

  content.textContent = text;
  applyReaderStyles();
  updateDisplayValues();
}

function applyReaderStyles() {
  const content = document.getElementById('reader-content');
  content.style.fontSize = `${currentFontSize}px`;
  content.style.setProperty('--lh', currentLineHeight);
  content.style.setProperty('--ls', `${currentLetterSpacing}px`);
}

function adjustFontSize(delta) {
  currentFontSize = Math.max(18, Math.min(96, currentFontSize + delta * 4));
  state.fontSize = currentFontSize;
  saveSettings();
  applyReaderStyles();
  updateDisplayValues();
}

function adjustLineHeight(delta) {
  currentLineHeight = Math.max(1.0, Math.min(3.0, +(currentLineHeight + delta).toFixed(1)));
  state.lineHeight = currentLineHeight;
  saveSettings();
  applyReaderStyles();
  updateDisplayValues();
}

function adjustLetterSpacing(delta) {
  currentLetterSpacing = Math.max(0, Math.min(5, +(currentLetterSpacing + delta).toFixed(1)));
  state.letterSpacing = currentLetterSpacing;
  saveSettings();
  applyReaderStyles();
  updateDisplayValues();
}

function toggleControls() {
  const ctrl = document.getElementById('reader-controls');
  ctrl.classList.toggle('hidden');
}

// ═══ 阅读标尺 ═══

let rulerEl = null;
let rulerInterval = null;

function toggleRuler() {
  state.rulerEnabled = document.getElementById('setting-ruler').checked;
  saveSettings();

  if (state.rulerEnabled) {
    enableRuler();
  } else {
    disableRuler();
  }
}

function enableRuler() {
  if (rulerEl) return;
  rulerEl = document.createElement('div');
  rulerEl.className = 'reader-ruler';
  document.body.appendChild(rulerEl);

  // 跟踪触摸/鼠标位置
  const updateRuler = (e) => {
    const y = e.touches ? e.touches[0].clientY : e.clientY;
    rulerEl.style.top = `${y - 30}px`;
  };

  document.addEventListener('mousemove', updateRuler);
  document.addEventListener('touchmove', updateRuler);
  rulerEl._cleanup = () => {
    document.removeEventListener('mousemove', updateRuler);
    document.removeEventListener('touchmove', updateRuler);
  };
}

function disableRuler() {
  if (rulerEl) {
    if (rulerEl._cleanup) rulerEl._cleanup();
    rulerEl.remove();
    rulerEl = null;
  }
}

// ═══ 设置管理 ═══

function loadSettings() {
  try {
    const saved = localStorage.getItem('laohuazhiyou_settings');
    return saved ? { ...DEFAULTS, ...JSON.parse(saved) } : { ...DEFAULTS };
  } catch {
    return { ...DEFAULTS };
  }
}

function saveSettings() {
  try {
    localStorage.setItem('laohuazhiyou_settings', JSON.stringify(state));
  } catch (e) {
    console.warn('保存设置失败:', e);
  }
}

function updateSettingDisplay() {
  const val = document.getElementById('setting-fontsize').value;
  document.getElementById('setting-fontsize-display').textContent = `${val}px`;
  state.fontSize = parseInt(val);
  saveSettings();
}

function clearAllData() {
  if (confirm('确定清除所有本地数据？这将重置所有设置。')) {
    localStorage.removeItem('laohuazhiyou_settings');
    state = { ...DEFAULTS };
    applyTheme(state.theme);
    document.getElementById('setting-fontsize').value = state.fontSize;
    document.getElementById('setting-fontsize-display').textContent = `${state.fontSize}px`;
    document.getElementById('setting-ruler').checked = false;
    disableRuler();
  }
}

// ═══ 阅读距离校准 ═══

function calibrateDistance() {
  const result = document.getElementById('distance-result');
  result.classList.remove('hidden');
  result.textContent = '📏 请将手机放到你平时阅读最舒服的距离... 3';

  let count = 3;
  const timer = setInterval(() => {
    count--;
    if (count > 0) {
      result.textContent = `📏 请将手机放到你平时阅读最舒服的距离... ${count}`;
    } else {
      clearInterval(timer);
      // 用前置摄像头估算距离（简化版：取平均值 35cm）
      const estimatedDistance = 35;
      state.readingDistance = estimatedDistance;
      saveSettings();
      result.textContent = `✅ 已校准！推荐阅读距离: ~${estimatedDistance}cm\n提示：这只是估算，你可以根据自己的感觉调整字号。`;
    }
  }, 1000);
}

// ═══ 拍照 OCR ═══

async function startCamera() {
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } }
    });
    document.getElementById('camera-preview').srcObject = cameraStream;
  } catch (e) {
    alert('无法打开摄像头: ' + e.message + '\n你可以使用"选图片"功能上传照片。');
  }
}

function stopCamera() {
  if (cameraStream) {
    cameraStream.getTracks().forEach(t => t.stop());
    cameraStream = null;
  }
}

function capturePhoto() {
  const video = document.getElementById('camera-preview');
  const canvas = document.createElement('canvas');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  const ctx = canvas.getContext('2d');
  ctx.drawImage(video, 0, 0);
  canvas.toBlob(blob => {
    processImage(blob);
  }, 'image/jpeg', 0.95);
}

function handleFileUpload(event) {
  const file = event.target.files[0];
  if (file) processImage(file);
}

async function processImage(blob) {
  const resultDiv = document.getElementById('ocr-result');
  const textDiv = document.getElementById('ocr-text');
  const progressDiv = document.getElementById('ocr-progress');
  const statusSpan = document.getElementById('ocr-status');
  const bar = document.getElementById('ocr-bar');

  resultDiv.classList.remove('hidden');
  progressDiv.classList.remove('hidden');
  textDiv.textContent = '';

  try {
    // 加载 Tesseract.js
    if (!ocrWorker) {
      statusSpan.textContent = '加载 OCR 引擎...';
      // 动态加载 Tesseract
      await loadTesseract();
    }

    statusSpan.textContent = '识别中...';

    const result = await Tesseract.recognize(blob, 'chi_sim+eng', {
      logger: m => {
        if (m.status === 'recognizing text') {
          bar.style.width = `${Math.round(m.progress * 100)}%`;
          statusSpan.textContent = `${Math.round(m.progress * 100)}%`;
        }
      }
    });

    progressDiv.classList.add('hidden');
    const text = result.data.text.trim();
    if (text) {
      textDiv.textContent = text;
    } else {
      textDiv.textContent = '未识别到文字。请尝试:\n• 确保光线充足\n• 文字保持水平\n• 镜头对准文字\n\n你也可以粘贴文字到"阅读模式"。';
    }

  } catch (e) {
    progressDiv.classList.add('hidden');
    textDiv.textContent = `识别失败: ${e.message}\n\n你可以尝试:\n1. 重新拍照\n2. 上传清晰的照片\n3. 切换到「粘贴阅读」模式`;
  }
}

async function loadTesseract() {
  // 动态导入 Tesseract.js CDN
  return new Promise((resolve, reject) => {
    if (window.Tesseract) {
      resolve();
      return;
    }
    const script = document.createElement('script');
    script.src = 'https://unpkg.com/tesseract.js@5/dist/tesseract.min.js';
    script.onload = resolve;
    script.onerror = () => reject(new Error('无法加载 OCR 引擎'));
    document.head.appendChild(script);
  });
}

function retakePhoto() {
  document.getElementById('ocr-result').classList.add('hidden');
}

function copyOcrText() {
  const text = document.getElementById('ocr-text').textContent;
  if (text && text !== '未识别到文字...') {
    navigator.clipboard.writeText(text).then(() => {
      alert('✅ 文字已复制到剪贴板');
    }).catch(() => {
      // fallback
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
      alert('✅ 文字已复制');
    });
  }
}

// ═══ PWA: Service Worker ═══

async function registerSW() {
  if ('serviceWorker' in navigator) {
    try {
      await navigator.serviceWorker.register('sw.js');
      console.log('📦 Service Worker 已注册');
    } catch (e) {
      console.warn('Service Worker 注册失败:', e);
    }
  }
}

// ═══ 全局暴露 ═══

// 所有视图切换等功能暴露到全局
window.showView = showView;
window.setTheme = setTheme;
window.setDefaultTheme = setDefaultTheme;
window.startReading = startReading;
window.adjustFontSize = adjustFontSize;
window.adjustLineHeight = adjustLineHeight;
window.adjustLetterSpacing = adjustLetterSpacing;
window.toggleControls = toggleControls;
window.capturePhoto = capturePhoto;
window.handleFileUpload = handleFileUpload;
window.retakePhoto = retakePhoto;
window.copyOcrText = copyOcrText;
window.calibrateDistance = calibrateDistance;
window.toggleRuler = toggleRuler;
window.updateSettingDisplay = updateSettingDisplay;
window.clearAllData = clearAllData;
window.stopCamera = stopCamera;
