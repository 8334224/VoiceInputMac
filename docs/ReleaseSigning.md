# Developer ID 签名与 notarization 准备清单

这份说明的目标不是一次性把发布工程做完，而是把正式公开 Beta 前的阻塞点收敛清楚。

当前项目状态：

- 已能通过 `./scripts/build_app.sh` 生成 `.app` 和 `.zip`
- 默认是 ad-hoc 签名
- 已适合小范围 Beta 分发
- 还没有 Developer ID Application 签名
- 还没有 notarization

## 1. 需要准备的 Apple Developer 资源

正式公开 Beta 前，至少需要：

### 必要资源

- 有效的 Apple Developer Program 账号
- `Developer ID Application` 证书
- 对应私钥已经安装在本机钥匙串
- 一个稳定的 `CFBundleIdentifier`
  - 当前脚本里是 `com.adi.voiceinputmac`

### notarization 所需资源

至少要准备其中一种认证方式：

- `notarytool` Keychain Profile
- 或 App Store Connect API key

推荐使用：

- `xcrun notarytool store-credentials`

这样后续脚本或命令行调用最稳定。

## 2. 当前 `build_app.sh` 离正式签名还差什么

当前脚本已经预留了最小入口：

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
```

当前脚本行为：

- 不传 `APP_SIGN_IDENTITY`
  - 继续走 ad-hoc 签名
- 传了 `APP_SIGN_IDENTITY`
  - 改为正式 `codesign`
  - 自动加 `--options runtime`

这意味着：

- 正式签名入口已经预留好了
- 但 notarization 还没有自动化进脚本

## 3. notarization 的最小流程

最小流程可以先手动执行，不一定要脚本化。

### 第一步：正式签名打包

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
```

产物：

- `dist/VoiceInputMac.app`
- `dist/VoiceInputMac-0.1.0-macOS.zip`

### 第二步：提交 notarization

如果已经保存好 `notarytool` 凭证：

```bash
xcrun notarytool submit "dist/VoiceInputMac-0.1.0-macOS.zip" \
  --keychain-profile "YOUR_NOTARY_PROFILE" \
  --wait
```

### 第三步：staple

如果 notarization 成功：

```bash
xcrun stapler staple "dist/VoiceInputMac.app"
```

### 第四步：重新打 zip

因为 stapling 发生在 `.app` 上，所以建议在 `staple` 后重新压一次：

```bash
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "dist/VoiceInputMac.app" \
  "dist/VoiceInputMac-0.1.0-macOS.zip"
```

## 4. 正式公开 Beta 前还要做哪些机器验证

至少做这几类：

### A. 全新机器首次下载验证

验证点：

- zip 解压是否正常
- `.app` 是否能直接打开
- Gatekeeper 是否还拦截
- 菜单栏是否正常出现

### B. 首次权限验证

验证点：

- 麦克风权限弹窗
- 语音识别权限弹窗
- 辅助功能权限引导
- 拒绝权限后能否按预期恢复

### C. 常见使用路径验证

验证点：

- 开始听写 / 结束听写
- 自动粘贴
- 热键改动后是否生效
- 退出时是否稳定

### D. 一台未安装 Xcode 的机器验证

这是正式公开 Beta 前必须做的一步，因为：

- 本机开发环境有大量隐式依赖
- 未装 Xcode 的机器更接近真实用户环境

## 5. 现在可以先准备好的内容

即使现在还没实操 Apple Developer 账号，也可以先准备：

- 固定 `CFBundleIdentifier`
- 固定版本号与 zip 命名策略
- 发布说明模板
- 安装说明
- 权限引导文档
- 常见报错 FAQ
- 一台干净机器上的验证清单

也就是说，现在完全可以先把：

- 文档
- 流程
- 验证 checklist

先准备好，等 Developer ID 和 notarization 账号条件到位后再实操。

## 6. 现在离正式公开 Beta 还差哪几步

按顺序看：

1. 准备 Apple Developer 账号和 `Developer ID Application`
2. 在本机钥匙串装好证书和私钥
3. 用 `APP_SIGN_IDENTITY` 跑正式签名
4. 配置 `notarytool` 凭证
5. 提交 notarization
6. `staple`
7. 在干净机器上做首次下载与权限验证
8. 再对外放出 zip

## 7. 当前哪些步骤只是文档化，哪些后面再落地

已经可以现在先完成的：

- 打包路径说明
- 安装说明
- 权限说明
- 常见报错说明
- 正式签名与 notarization 操作清单
- `build_app.sh` 的正式签名入口预留

后面再落地的：

- 自动 notarization 脚本
- stapling 后自动重新打包
- CI/CD 发布流程
- release artifact 自动上传
