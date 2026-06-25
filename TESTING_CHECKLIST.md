# PresbyFriend 测试清单 (2026-06-23)

---

## iOS 端 (模拟器 / 真机)

### 1. 底部导航
- [ ] 两个图标：🔍（放大镜）+ ⚙️（设置），无文字
- [ ] 点 🔍 → 进入放大镜/主页
- [ ] 点 ⚙️ → 进入设置页

### 2. 放大镜页（模拟器）
- [ ] 显示放大镜图标 + 说明信息："Camera unavailable"
- [ ] 有 "See how reading works" 演示按钮
- [ ] 点演示按钮 → 进入阅读页，可调节字号/主题/朗读
- [ ] 左上角 Close 返回

### 3. 放大镜页（真机）
- [ ] 允许相机权限后显示实时预览
- [ ] 可缩放（滑块拖动）
- [ ] 手电筒开关
- [ ] 对准文字 → 点高亮区域 → 进入阅读页
- [ ] 左上角 Close 返回

### 4. 剪贴板自动检测
- [ ] 先在 Safari/备忘录复制一段文字
- [ ] 切换到 PresbyFriend（或重新打开）
- [ ] 自动进入阅读页，显示刚复制的文字
- [ ] 左上角 Close 返回主页

### 5. 阅读页
- [ ] 右上角 **▶** 按钮 → 开始朗读（中文自动用中文语音）
- [ ] 朗读中图标变 **⏹** → 点一下停止
- [ ] 右上角 **Aa** 按钮 → 弹出控件面板
- [ ] 字号 +/- 按钮调节（24-72），文字实时变化
- [ ] 4 个主题色块点击切换（白/深褐/深色/黄）
- [ ] 行高 +/- 调节
- [ ] 字间距 +/- 调节
- [ ] 左上角 Close 返回主页

### 6. 阅读标尺
- [ ] 设置页 → 打开 "Reading Ruler" 开关
- [ ] 进入阅读页 → 底部出现高亮条
- [ ] 手指在文字上拖动 → 高亮条跟随移动

### 7. 设置页
- [ ] Default Font Size：+/- 按钮 + 滑块调节
- [ ] 旁边的数字预览实时变化
- [ ] Default Theme：4 个色块选择
- [ ] Reading Ruler 开关
- [ ] Language 下拉 → 选 Deutsch → 界面文字变德语
- [ ] 再选回 English → 界面变回英语
- [ ] 选其他语言（Français/Italiano/Español/Português）各测试一遍
- [ ] "Upgrade to Pro" → 弹出付费页

### 8. 设置实时生效
- [ ] 调字号到最大 → 回主页 → 复制文字 → 阅读页字号应该是刚才设的
- [ ] 调主题到黄色 → 阅读页背景应该是黄色
- [ ] 调行高到最大 → 阅读页行间距应该变大

### 9. 付费页
- [ ] 👑 图标 + "Upgrade to Pro" 标题
- [ ] 显示解释文字 "You have reached the 10 free reads..."
- [ ] 两个价格卡片（$2.99/mo, $19.99/yr）
- [ ] 点价格卡片 → 底部弹提示 "Purchase will be available on the App Store..."
- [ ] 提示 2 秒后自动消失
- [ ] "Restore Purchases" 按钮 → 显示 "No previous purchases found."
- [ ] Close 按钮关闭

### 10. 分享扩展
- [ ] 在 Safari 打开任意网页
- [ ] 选一段文字 → 点 "共享…"
- [ ] 在共享菜单找到 PresbyFriend 图标 → 点击
- [ ] 弹出阅读卡片，显示选中的文字
- [ ] 卡片中可调节字号/主题/朗读
- [ ] 点 Close/Done 关闭

### 11. 语言切换
- [ ] 设置 → Language → 依次测试 6 种语言
- [ ] 每种语言切换后，设置页和主页文字应该变化
- [ ] 阅读页的 "Reading Mode" 标题也跟随变化

---

## Android 端

### 12. 首页
- [ ] 启动 App → 首页 "Reading Assistant for Presbyopia"
- [ ] "Magnifier" 按钮 + "Enable Floating Button" + "Settings"

### 13. 放大镜
- [ ] 点 Magnifier → 相机画面 + 底部缩放条 + 手电筒
- [ ] 识别到的文字块显示在顶部（点一下进入阅读）
- [ ] 缩放滑块 + 手电筒开关

### 14. 阅读页
- [ ] 顶部 "Read"/"Stop" 按钮 TTS 朗读
- [ ] "Aa" 按钮弹出控件面板
- [ ] 字号滑块 24-72
- [ ] 4 个主题色块
- [ ] 行高 / 字间距滑块
- [ ] Reading Ruler 开关
- [ ] Close 返回

### 15. 设置页
- [ ] Default Font/Theme/Ruler/Language
- [ ] 语言下拉切换（应用 locale + recreate）
- [ ] Upgrade to Pro → 付费页
- [ ] Reset Settings

### 16. 付费页
- [ ] 加载 Google Play 商品（或兜底价格）
- [ ] Restore Purchases

### 17. 分享接收
- [ ] 从其他 App 选文字 → Share → PresbyFriend
- [ ] 直接进入阅读页
- [ ] 分享 URL 也一样

### 18. 无障碍服务
- [ ] 开启无障碍服务 → 桌面出现悬浮按钮
- [ ] 在其他 App 中点悬浮按钮 → 截图 OCR → 阅读页
- [ ] 每日限制（代码已注释供测试）
