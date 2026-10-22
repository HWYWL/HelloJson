# 🎉 HelloJson v0.1.0-20261022 更新啦

> 一个把 JSON 变成「看得见」的原生鸿蒙小工具 ✨

---

## 🆕 这次更新真的有点多，建议收藏慢慢看

### 🧭 菜单终于顺手了

以前点「工具」会"唰"地弹出一张大卡片，糊在屏幕中间偏下，还得找关闭按钮 🔍

现在全部改成**贴着按钮往下掉**的下拉菜单 —— 文件 / 工具 / 查询 / 生成 / 导出，点哪儿弹哪儿，指哪打哪 👌

### 🎨 编辑器会「上色」了

键名蓝、字符串橙、数字绿、布尔紫、null 灰，配色完全跟着主题走 🌈

格式化之后自动切到「高亮」模式，类型一眼分清；想手改？点一下编辑器就回「编辑」模式 ✍️

### 📦 示例数据四合一

文件 → 载入示例数据，左侧面板直接选 **JSON / YAML / CSV / XML**

后三者会自动转成 JSON 再画成图，载入前还会先清空旧数据，不会串场 🧹

### ↔️ 左右分栏随便拖

中间那条分隔条可以拖了，18% ~ 82% 随你调 🖐

更贴心的是：格式化后左栏会**按最长那行自动收窄**，短 JSON 不再留一大片空白，右边画布也不会被挤成一小块（最多只占一半）

### 📊 状态栏信息量拉满

节点 / 边 / 行数 / 字符数 / JSON 是否有效（出错会标行号）/ 选中路径 / 匹配数 / 视图 / 布局方向 / 缩放 / 编辑模式

底部那一小条，现在能看的东西可太多了 👀

### 🐛 修了这些

- 右下角 `⤢` 按钮点了毫无反应 → 现在是一键全屏 / 退出全屏
- 「运行环境」写错了：API 24 对应的是 **HarmonyOS 6.1.1**，不是 6.0

### 🧑‍💻 新增「关于」

顶栏最右侧新按钮：版本号自动读取、项目地址点一下直接跳浏览器、作者一叶秋枫

### 🖼 换了新图标

新拟态（Neumorphism）风格：哑光蓝底 + 白色浮雕大括号 + 下方 `JSON`

桌面上一眼就能认出来 💙

---

## 📮 版本号怎么读

`v0.1.0-20261022`

- 第 1 位：大版本，重大更新才动（**慎之又慎**）
- 第 2 位：新增功能
- 第 3 位：修 bug / 优化代码
- `-` 后面：编译日期

## 📦 本次发布的安装包

`v0.1.0-20261022-unsigned.hap`（未签名）

未签名包**不能直接 `hdc install`**，会报 `9568322 signature verification failed`。想跑起来有两种方式：

1. 用 DevEco Studio 打开工程 → `File > Project Structure > Signing Configs` → 勾选 `Automatically generate signature` → 直接 Run，或重新打包
2. 用自己的证书手动签名后再装：
   ```bash
   java -jar hap-sign-tool.jar sign-app -mode localSign -keyAlias <别名> \
     -appCertFile <证书.cer> -profileFile <profile.p7b> \
     -inFile v0.1.0-20261022-unsigned.hap \
     -signAlg SHA256withECDSA -keystoreFile <密钥.p12> -keystorePwd <密码> \
     -keyPwd <密码> -outFile HelloJson-signed.hap -compatibleVersion 24 -signCode 1
   hdc install -r HelloJson-signed.hap
   ```

不提供已签名包，是因为调试证书和 profile 都绑定了具体设备 UDID，公开分发没意义 🙃

## 💻 运行环境

HarmonyOS 6.1.1+（API 24+）

## 🔗 项目地址

https://github.com/HWYWL/HelloJson

#鸿蒙开发 #HarmonyOS #ArkTS #JSON #开发者工具 #开源
