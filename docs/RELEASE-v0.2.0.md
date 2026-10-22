# 🗂 HelloJson v0.2.0-20261022 更新啦

> 多标签来了！一个窗口同时开好几个 JSON，切来切去不打架 ✨

---

## 🆕 这次最大的变化：多标签

### 🏷 编辑区顶部多了一排小标签

- 点「＋」新建，点标签切换，点「✕」关闭 👆
- 当前标签高亮，改过还没保存的会带一个小圆点 🔴
- 全屏看图形时，标签条会跟着编辑区一起收起来，不挡视线

### 🖱 右键标签，三个选项一步到位

- **关闭**：关掉这一个
- **关闭其他**：只留右键的这个，并立刻切过去
- **全部关闭**：清空后自动留一个空白标签，不会出现"一个都没有"的尴尬

菜单只作用于**你右键的那个标签**，不会偷偷切换当前标签 👌

### 🧠 每个标签各过各的

正文、解析报错、图形、树视图、折叠状态、选中路径、查找状态，全都互不干扰 🙌

而主题、图形/树视图、编辑/高亮、分栏比例还是**全局共享**的，切标签不会突然跳一下

### 💾 关掉再开，标签还在

所有标签 + 当前激活的那个都会记住；
老版本只有一份文本？会自动迁移成第一个标签，内容不丢 🧳

### 📥 打开即新标签

打开文件 / 从 URL 导入 / 从剪贴板粘贴，都会自动开一个新标签；
保存成功后标签名直接变成文件名，小圆点消失 ✍️

### 🐛 顺手修了这些

- 空标签不再顶着「第 0 行: 解析失败」的红字，底栏改成「空文档」
- 切标签时不会再残留上一个文档的图形

### 🧱 底层也翻新了

原来 2600 多行的主页面，拆成了顶栏 / 编辑区 / 图形区 / 树视图 / 结果区 / 浮层面板等独立组件，
状态统一交给一个共享数据层收拾。以后加功能不用再在超长文件里摸黑了 🧑‍💻

---

## 📮 版本号怎么读

`v0.2.0-20261022`

- 第 1 位：大版本，重大更新才动（**慎之又慎**）
- 第 2 位：新增功能
- 第 3 位：修 bug / 优化代码
- `-` 后面：编译日期

这次是「新增功能」，所以第 2 位 +1，从 0.1.0 走到 0.2.0 🚀

## 📦 本次发布的安装包

`v0.2.0-20261022-unsigned.hap`（未签名）

未签名包**不能直接 `hdc install`**，会报 `9568322 signature verification failed`。想跑起来有两种方式：

1. 用 DevEco Studio 打开工程 → `File > Project Structure > Signing Configs` → 勾选 `Automatically generate signature` → 直接 Run，或重新打包
2. 用自己的证书手动签名后再装：

   ```bash
   java -jar hap-sign-tool.jar sign-app -mode localSign -keyAlias <别名> \
     -appCertFile <证书.cer> -profileFile <profile.p7b> \
     -inFile v0.2.0-20261022-unsigned.hap \
     -signAlg SHA256withECDSA -keystoreFile <密钥.p12> -keystorePwd <密码> \
     -keyPwd <密码> -outFile HelloJson-signed.hap -compatibleVersion 24 -signCode 1
   hdc install -r HelloJson-signed.hap
   ```

不提供已签名包，是因为调试证书和 profile 都绑定了具体设备 UDID，公开分发没意义 🙃

## 💻 运行环境

HarmonyOS 6.1.1+（API 24+）

## 🔗 项目地址

https://github.com/HWYWL/HelloJson

#鸿蒙开发 #HarmonyOS #ArkTS #JSON #开发者工具 #开源 #多标签
