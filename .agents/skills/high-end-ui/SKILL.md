---
name: high-end-ui
description: |
  大厂级 UI 质感与 AI 客户端高定设计规范。消灭前端界面的“廉价塑料味”，注入大厂源码级质感。
  包含：1%~3% 微明度色阶分层、暗色模式视网膜字重补偿、水墨晕染流式打字、等宽数字防抖、Grid 免 JS 平滑折叠、动效性格阻尼学（过阻尼咬死 vs 欠阻尼 Q 弹）、临时反馈 2.5 秒自熄等 10 条铁律与即插即用代码模板。
  触发方式：/high-end-ui、高定UI、界面优化、前端质感、消灭塑料味、大厂UI规范、AI客户端设计
---

# high-end-ui：大厂级 AI 客户端前端高定质感规范

你是一名**资深前端视觉与交互体验架构师**，精通 Linear、Claude、Raycast、Vercel 等顶级大厂客户端的底层设计哲学与源码级细节。

普通 AI 生成或新手编写的前端界面往往散发着一股说不出的**“廉价塑料味”**：生硬粗糙的 1px 黑色边框、纯黑背景刺眼反光、打字输出像机关枪生硬硬蹦、计数器数字跳动时整行乱晃、动效要么全无要么轻浮乱颤。

本技能的目标是：**通过 5 大魔鬼细节与 10 条高定铁律，用纯粹的 CSS 与结构化交互，让你的前端与 AI 聊天应用质感原地封神。**

---

## 核心哲学：大厂质感从何而来？

1. **去线条化，靠微明度色阶建立空间深度**：不画刺眼的框，靠 1%~3% 的微明度差自然浮动。
2. **欺骗人眼，而非信赖机械参数**：暗色模式光晕让白字发胖，代码参数故意下调，人眼感知才平衡。
3. **有机的流动，拒绝机械闪烁**：打字是水墨晕开的波浪，不是字符的生硬插入。
4. **恪守排版铁律，消灭微小抖动**：数字必锁等宽，末行必防孤字，折叠由网格接管。
5. **动效具备性格与克制**：结构操作瞬间咬死（过阻尼 0% 回弹），情感反馈欢快轻盈（欠阻尼微弹），临时状态 2.5 秒自熄绝不占地。

---

## 十条高定 UI 铁律对照表

| 序号 | 维度 | ❌ 新手/塑料味做法 | ✅ 大厂高定源码级做法 | 核心技术点 |
| :--- | :--- | :--- | :--- | :--- |
| **01** | **层次分层** | 到处画 1px 边框、深黑硬套卡片 | **禁止纯黑 #000**，靠 **1%~3% 微对比明度阶梯** 分层 | `Surface 0~3` 微对比色阶 |
| **02** | **输入框聚焦** | 聚焦时加突兀生硬的亮色 `outline` | 聚焦不加 outline，用**外阴影 + inset 内阴影双环加深** | 温润咬合感 Box-shadow |
| **03** | **暗色排版** | 亮暗模式文字粗细完全相同 | **字重全站整体悄悄下调 40**（如 400→360） | 视网膜光晕效应补偿 |
| **04** | **流式输出** | 字符像机关枪一样硬蹦闪烁 | **单字带 90ms~120ms 高斯模糊渐显**，相邻错开 30ms | 水墨晕染波浪动效 |
| **05** | **行内图标** | 图标贴基线导致重心偏高飘浮 | 图标统一**下挪 1/8 个字高（-0.125em）** | 图标与文字几何中心对齐 |
| **06** | **数字展示** | 计时/数值变化时整行左右晃动 | 强制开启 **`font-variant-numeric: tabular-nums;`** | 等宽数字锁死防乱抖 |
| **07** | **伸缩折叠** | 用 JS 算 `scrollHeight` 动效卡顿 | 纯 CSS **`grid-template-rows: 0fr → 1fr;`** | 自适应网格丝滑展开 |
| **08** | **文本换行** | 最后几个字孤零零掉到第二行 | 正文段落启用 **`text-wrap: pretty;`** | 自动平摊末行消灭孤字 |
| **09** | **动效性格** | 全局统一 bounce 或无脑 0.3s ease | **拖拽吸附用过阻尼零回弹，点赞轻反馈用欠阻尼微弹** | 物理弹簧阻尼分级 |
| **10** | **反馈生命周期** | 复制对勾永久留存或依赖弹窗 | 成功反馈状态 **2.5 秒后自动平滑淡出复原** | `setTimeout(hide, 2500)` 反馈自熄 |

---

## 源码级实现方案与代码库

### 1. 微明度色阶分层与输入框咬合感（铁律 1 & 2）

#### CSS 变量体系 (Design Tokens)
```css
/* 浅色模式微阶梯（明度差 1% ~ 3%） */
:root {
  --surface-0: #f5f5f3; /* 页面最底层背景 */
  --surface-1: #fcfcfb; /* 卡片/容器层 */
  --surface-2: #ffffff; /* 悬浮层/输入区 */
  --border-subtle: rgba(0, 0, 0, 0.04);
}

/* 暗色模式微阶梯（拒绝纯黑 #000，微阶梯深灰） */
.dark {
  --surface-0: #0b0b0a; /* 最底层画布：禁纯黑 #000 */
  --surface-1: #151515; /* 侧边栏/容器层 */
  --surface-2: #1a1a19; /* 内容卡片/输入框默认态 */
  --surface-3: #20201e; /* 悬停/激活态 */
  --border-subtle: rgba(255, 255, 255, 0.05);
}
```

#### 输入框温润咬合感 (Input Focus State)
```css
/* 拒绝生硬高亮的外圈 line，打造物理按压质感 */
.high-end-input {
  background-color: var(--surface-2);
  border: 1px solid var(--border-subtle);
  border-radius: 10px;
  color: inherit;
  padding: 10px 14px;
  transition: box-shadow 0.2s cubic-bezier(0.16, 1, 0.3, 1), 
              background-color 0.2s ease;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}

.high-end-input:focus {
  outline: none; /* 坚决去掉浏览器默认粗轮廓 */
  background-color: var(--surface-1);
  /* 双环阴影：微弱外圈光晕 + 内部微弱下陷咬合感 */
  box-shadow: 
    0 0 0 1px rgba(255, 255, 255, 0.1),
    0 4px 16px -2px rgba(0, 0, 0, 0.35),
    inset 0 1px 2px rgba(0, 0, 0, 0.25);
}
```

---

### 2. 视网膜光晕欺骗术：暗色模式字重微调（铁律 3）

人眼具有光渗效应（Optical Irradiation），暗底上的白字视觉上会向外辐射发胖 10%~15%。必须在暗色模式下主动调细代码参数：

```css
/* 引入可变字体 Variable Font (如 Inter, PingFang SC, Geist) */
:root {
  --font-regular: 400;
  --font-medium: 500;
  --font-semibold: 580;
  --font-bold: 600;
}

/* 暗色模式人眼补偿：字重整体悄悄调细 40 */
.dark {
  --font-regular: 360;
  --font-medium: 460;
  --font-semibold: 540;
  --font-bold: 560;
}

body {
  font-weight: var(--font-regular);
}

h1, h2, h3, strong {
  font-weight: var(--font-bold);
}
```

---

### 3. 水墨晕染式流式打字与行内图标下沉（铁律 4 & 5）

#### 水墨晕染打字动画 (Ink Diffusion Streaming)
```css
/* 单字符水墨显影动画 */
@keyframes ink-bloom {
  0% {
    filter: blur(6px);
    opacity: 0;
    transform: translateY(1px);
  }
  100% {
    filter: blur(0);
    opacity: 1;
    transform: translateY(0);
  }
}

.stream-char {
  display: inline-block;
  animation: ink-bloom 100ms cubic-bezier(0.215, 0.61, 0.355, 1) forwards;
  will-change: filter, opacity;
}
```

*实现逻辑*：AI 流式 chunk 推送时，每产生一个字符，赋予对应延时（相邻字符错开 25ms~30ms），当前字尚未完全清晰，下一个字已开始晕开，呈现水墨波浪。

#### 行内图标微距下沉 (Sub-pixel Alignment)
```css
/* 修正 SVG 图标因基线漂浮在字头的问题 */
.inline-icon,
svg.inline {
  vertical-align: -0.125em; /* 悄悄下挪 1/8 个字高 */
  display: inline-block;
  fill: currentColor;
}
```

---

### 4. 两行代码治好乱抖与排版强迫症（铁律 6、7、8）

#### 等宽数字防抖 (Tabular Numbers)
```css
/* 适用于：耗时计时器 (思考中 12秒)、Token 计数、价格变动、列表索引 */
.tabular-nums,
.timer-display,
.stat-counter {
  font-variant-numeric: tabular-nums;
  font-feature-settings: "tnum" 1;
}
```

#### 纯 CSS 自适应网格丝滑折叠展开 (Grid Collapsible)
```html
<!-- HTML 结构 -->
<div class="collapsible-wrapper open">
  <div class="collapsible-inner">
    <p>这里是思考过程内容...</p>
  </div>
</div>
```

```css
/* 纯 CSS 解决 height: auto 无法加过渡的大难题 */
.collapsible-wrapper {
  display: grid;
  grid-template-rows: 0fr;
  transition: grid-template-rows 240ms cubic-bezier(0.16, 1, 0.3, 1);
}

.collapsible-wrapper.open {
  grid-template-rows: 1fr;
}

.collapsible-inner {
  overflow: hidden;
  min-height: 0; /* 必须设置，否则 flex/grid 默认 min-height: auto 会阻碍折叠 */
}
```

#### 排版防孤字 (Text Wrap Pretty)
```css
/* 终结段落末尾单个字掉在第二行的灾难 */
p, .article-body, .message-bubble {
  text-wrap: pretty;
}
```

---

### 5. 动效性格学与反馈自熄（铁律 9 & 10）

#### 动效性格口诀
> **“拖拽吸附要雷厉风行，点赞反馈要欢快 Q 弹。”**

#### A. 结构操作（侧边栏拖拽、面板停靠、抽屉）—— 过阻尼瞬间咬死
- **物理特性**：0% 回弹，极速到位，零延迟。
- **Spring 参数**：`stiffness: 1200, damping: 80`
- **CSS 近似缓动**：`transition-timing-function: cubic-bezier(0.16, 1, 0.3, 1);`

#### B. 情感轻反馈（点赞、收藏、复制对勾）—— 欠阻尼欢快 Q 弹
- **物理特性**：约 15%~20% 适度微回弹，富有生机。
- **Spring 参数**：`stiffness: 380, damping: 18`

```css
/* CSS 模拟欠阻尼轻微回弹 */
@keyframes pop-bounce {
  0% { transform: scale(0.85); opacity: 0; }
  60% { transform: scale(1.15); opacity: 1; }
  100% { transform: scale(1); }
}

.feedback-pop {
  animation: pop-bounce 300ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
```

#### C. 反馈自熄法则 (Auto-extinguish Lifecycle)
任何瞬态成功反馈（如点击“复制”后变成“绿色对勾”），必须在 **2.5 秒（2500ms）** 准时自动淡出复原，绝不赖在界面上占地方。

```tsx
// React Hook / 组件示例
import React, { useState } from 'react';

export function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    // 2.5 秒反馈自熄铁律
    setTimeout(() => {
      setCopied(false);
    }, 2500);
  };

  return (
    <button onClick={handleCopy} className="p-1.5 rounded-md hover:bg-surface-3 transition">
      {copied ? (
        <CheckIcon className="inline-icon text-emerald-500 feedback-pop" />
      ) : (
        <CopyIcon className="inline-icon text-neutral-400" />
      )}
    </button>
  );
}
```

---

## 一键注入提示词 (Prompt Snippet)

当指派其他 AI 或生成前端页面代码时，将以下段落直接复制进提示词末尾，即可一键约束其输出符合大厂高定质感：

```text
【高定 UI 与前端质感铁律】
严格遵守顶级 AI 客户端源码级 10 条高定规范：
1. 去边框化：禁止全站画 1px 黑线，禁止纯黑 #000。浅色使用 #f5f5f3/#fcfcfb，暗色使用 #0b0b0a/#151515/#1a1a19/#20201e 依靠 1%~3% 微明度拉开空间深度。
2. 输入框质感：聚焦时不加突兀生硬的 outline，改用外阴影 + inset 内阴影双环加深，制造温润物理咬合感。
3. 暗色视网膜补偿：暗色模式文字粗细整体下调 40（如 400→360），避免人眼光晕效应让白字发胖刺眼。
4. 水墨流式打字：流式输出字符单字 90ms~120ms 从 blur(6px) 渐显至清晰（cubic-bezier(.215,.61,.355,1)），相邻字符错开 25~30ms 依次晕开。
5. 行内图标对齐：正文内的行内 SVG 统一添加 vertical-align: -0.125em，下沉 1/8 个字高对齐文字几何中心。
6. 数字防乱抖：所有动态数字、计时器、计费信息强制添加 font-variant-numeric: tabular-nums 锁死等宽。
7. 丝滑折叠展开：折叠面板绝不用 JS 计算 scrollHeight，改用纯 CSS grid-template-rows: 0fr → 1fr 过渡。
8. 排版防孤字：正文段落添加 text-wrap: pretty，消灭落单单字。
9. 动效性格学：拖拽/抽屉/吸附采用过阻尼弹簧（stiffness: 1200, damping: 80）零回弹瞬间咬死；点赞/复制轻反馈采用欠阻尼（stiffness: 380, damping: 18）欢快微弹。
10. 反馈自熄：复制对勾等成功状态必须在 2.5 秒后自动淡出恢复原状。
```

---

## 交付前自查清单 (Preflight Checklist)

- [ ] 页面中是否存在刺眼的纯黑 `#000000`？（应替换为 `#0b0b0a` 或微阶梯深灰）
- [ ] 卡片与侧边栏是否还在依赖生硬的深色边框？（应改为微对比背景色拉开层次）
- [ ] 输入框聚焦时是否有生硬突兀的蓝色/高亮线？（应使用双环阴影咬合）
- [ ] 暗色模式下文字是否显得过于臃肿油腻？（字重是否下调 40）
- [ ] 动态计时器或数字跳动时，容器或旁边文本是否在左右乱晃？（是否加了 `tabular-nums`）
- [ ] 行内图标的垂直位置是否偏高？（是否设置了 `vertical-align: -0.125em`）
- [ ] 折叠面板展开收起是否顿挫生硬？（是否采用了 `grid-template-rows: 0fr -> 1fr`）
- [ ] 复制成功的小对勾是否一直挂在界面上？（是否严格设置了 2.5 秒自熄）
