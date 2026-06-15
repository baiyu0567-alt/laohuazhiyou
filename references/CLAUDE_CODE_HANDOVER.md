# PresbyFriend (老花之友) — 项目交接手册

本文件是为 Claude Code 准备的完整项目背景资料。请先阅读本文，再阅读源代码。

---

## 一、项目定位

**一句话：** 让 40+ 岁老花眼用户在不戴老花镜的情况下，舒适地阅读手机/电脑上的小字。

**产品形态：** PWA（Progressive Web App），已验证可行性，当前为 v0.1，目标是先验证需求再考虑原生。

**当前状态：** v0.1 MVP，已部署到 Vercel（https://laohuazhiyou.vercel.app），有中英文双语界面，默认英文。

---

## 二、为什么要做这个产品

### 来自 Reddit 的真实需求调研

用 Hermes Agent 的 `findreqinreddit` skill 扫描 Reddit 发现：

| 帖子 | 热度 | 核心痛点 |
|------|------|---------|
| r/Xennials "difficult to read small text" | 510👍/251💬 | 42岁突然看不清药瓶小字 |
| r/Xennials "increased font size" | 329👍/64💬 | "调大字号就是新时代的老花镜" |
| r/AskWomenOver40 "near vision terrible" | 256👍/211💬 | 医生说"别戴老花镜"但没替代方案 |
| r/Perimenopause "eyesight gone" | 222👍/107💬 | 40岁，9个月内视力从完美到模糊 |
| r/Perimenopause (first session) | 136👍/145💬 | 渐进眼镜不适，被迫带3副眼镜切换 |
| r/cscareerquestions "read the screen" | 61👍/60💬 | IT从业者42岁，屏幕字体越来越小 |

**总参与度：1,187+ upvotes / 598+ 评论，零个 app 被提及为解决方案。**

### 竞品扫描

| 现有"方案" | 为什么不够好 |
|-----------|------------|
| 老花镜 | 随身带、到处丢、医生说"别依赖" |
| 渐进眼镜 | 头晕、头痛、需漫长适应期 |
| 系统字号放大 | 粗暴、UI会变形、无法放大特定区域 |
| 手机自带放大镜 | 功能单一，只能放大不能优化 |
| Sol Reader / Even Realities G1 | 硬件，$350-600，门槛高 |

### 核心洞察

40-45 岁是第一波老花发作期，这批用户：
- 从"视力一直很好"到"突然看不清"——心理冲击大
- 每天看手机 4+ 小时——刚需场景
- 不愿意接受"老花镜"——觉得显老、麻烦
- 有消费能力——愿意为舒适付费
- **没有任何 app 解决这个问题**

---

## 三、产品定义

### 核心价值主张

> 让用户在不戴老花镜的情况下看清手机小字。

### 目标用户

- **Primary:** 40-50 岁，每天看手机 4+ 小时，刚发现老花
- **Secondary:** 50+，已戴老花镜但觉得不方便
- **Tertiary:** IT/文字工作者，每天看屏幕 8+ 小时

### 功能路线图（按优先级）

#### v0.1（当前）— 验证核心价值
- [x] 粘贴/打字阅读（大字号优化显示）
- [x] 四种视觉主题（白/暖/暗/黄底）
- [x] 字号/行距/字间距可调
- [x] PWA（可安装到手机桌面，离线可用）
- [x] 中英文双语（默认英文，可切换中文）
- [x] 阅读标尺（高亮当前行，减少跳行）
- [x] 阅读设置记忆（localStorage）
- [ ] 拍照 OCR 阅读（Tesseract.js，需优化）
- [ ] 阅读距离校准（需完善）

#### v0.2 — 打磨核心体验
- [ ] OCR 准确率提升（更好的图像预处理）
- [ ] URL 内容提取优化（当前用 allorigins.win 代理不稳定）
- [ ] 相机拍照体验改善（自动对焦提示、连拍选最佳）
- [ ] 首次使用引导流程
- [ ] 更好的阅读距离校准

#### v1.0 — 原生 iOS
- [ ] 原生重写（Swift/SwiftUI）
- [ ] Live Text 集成（iOS 16+ 自带 OCR，精度远超 Tesseract.js）
- [ ] 系统辅助功能集成（屏幕覆盖层）
- [ ] App Store 发布 + IAP

#### 后续
- [ ] Android 版
- [ ] 付费/订阅模式

---

## 四、技术架构

### 当前技术栈

```
前端: 原生 HTML + CSS + JavaScript（无框架）
PWA:  manifest.json + Service Worker
OCR:  Tesseract.js（浏览器端，支持中英文）
存储: localStorage
部署: Vercel（自动从 GitHub 部署）
仓库: https://github.com/baiyu0567-alt/laohuazhiyou（私人仓库）
```

### 项目文件结构

```
laohuazhiyou/
├── index.html           ← 主页面（4个视图：首页/阅读器/拍照/设置）
├── manifest.json        ← PWA 清单
├── sw.js                ← Service Worker（离线缓存）
├── vercel.json          ← Vercel 部署配置
├── css/style.css        ← 所有样式
└── js/app.js            ← 所有逻辑（含 i18n 翻译、OCR、阅读器）
```

### i18n 实现

- 翻译表在 `app.js` 的 `I18N` 对象中（en + zh）
- 使用 `data-i18n` 属性标记需要翻译的 HTML 元素
- `renderUI()` 函数扫描并替换文本
- 默认英文（因 Reddit 用户是英文受众）

### 已知的技术问题

1. **Vercel 部署 404** — 从服务器测 HTTP 200 正常，但作者手机访问报 404，可能是 CDN/区域问题。已添加 `vercel.json` 配置，可能需要检查 Vercel 项目设置是否正确。
2. **URL 内容提取** — 使用 `api.allorigins.win` 作为代理，不稳定。建议替换为更可靠的方案或直接去掉此功能。
3. **Tesseract.js** — 在手机上加载较慢（~10-20MB），且识别精度有限。v1.0 原生 iOS 可用 Live Text 替代。
4. **Home 页面 emoji 重复** — `data-i18n` 文本中包含了 emoji，与 HTML 中已有的 emoji 重复显示。

---

## 五、关键设计决策

### 为什么先做 PWA 而不是原生？

1. **零分发门槛** — 不需要 App Store 审核，URL 即上线
2. **跨平台验证** — 一套代码同时验证 iOS 和 Android 用户
3. **快速迭代** — 推送即更新
4. **成本** — 零开发成本验证需求

### 为什么默认英文？

因为种子用户来自 Reddit（英文社区），先服务他们，验证产品价值。中文用户是第二阶段。

### 为什么不做系统级辅助功能？

讨论过但决定先做独立 app 验证：
- 系统级需要原生开发，PWA 做不到
- 系统级权限审批周期长
- 先用独立 app 验证需求真实，再考虑原生

---

## 六、商业模式

### 方案（待验证）

- **免费版：** 基础阅读功能
- **Pro 版：** $2.99/月 或 $19.99/年
  - 无限 OCR
  - 高级主题/自定义
  - 优先新功能

### 种子用户获取

第一批用户来自 Reddit 相关帖子的回复引流：
- r/Xennials (510👍)
- r/AskWomenOver40 (256👍)
- r/Perimenopause (222👍)
- r/cscareerquestions (61👍)

---

## 七、开发指引

### 运行

```bash
# 本地测试 - 用 Python 起一个 HTTP 服务器
cd laohuazhiyou && python3 -m http.server 8080
# 浏览器打开 http://localhost:8080
```

### 部署

推送到 GitHub master 分支 → Vercel 自动部署（需先在 Vercel 导入仓库）

### 添加新语言

1. 在 `app.js` 的 `I18N` 对象中添加新语言的翻译
2. 在 HTML 中添加 `data-i18n` 属性
3. 在 `setLanguage()` 中添加语言选项

### 关键文件说明

- `app.js` 是所有逻辑的集中地（约 500 行），建议按功能拆分为多个模块
- `style.css` 使用 CSS 变量实现主题切换，新增主题只需添加变量集
- `index.html` 使用视图切换模式（各视图独立 div），适合拆分为组件

---

## 八、致 Claude Code

以上是完整的项目背景。请先读此文档，再读源代码。

**当前最优先改进：**
1. 修复 Vercel 部署问题，确保手机端可访问
2. 优化 OCR 加载速度和识别精度
3. 修复已知 UI 问题（emoji 重复、allorigins 代理不稳定）
4. 完善首次使用引导

**用户偏好：**
- 用中文沟通
- 先用 PWA 验证需求，再考虑原生
- 注重实用性，不要过度设计
