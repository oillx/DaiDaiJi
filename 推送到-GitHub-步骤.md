# 把袋袋集推送到 GitHub

仓库地址：`git@github.com:oillx/DaiDaiJi.git`

沙箱里已经完成了一个本地提交（`85a2de0`，59 个文件）。你要做的只是把它推上去。

---

## 方案 A：你本地已有这个仓库，直接推（最快）

如果 `/workspace/DaiDaiJi` 这份代码就是你 Mac 上的那份：

```bash
cd <你的项目目录>
git init                      # 若还不是仓库
git remote add origin git@github.com:oillx/DaiDaiJi.git
git add -A
git commit -m "feat: 袋袋集 iOS 工程首次提交"
git push -u origin main
```

**SSH 首次使用需要配置密钥**（一次性）：

```bash
ssh-keygen -t ed25519 -C "你的邮箱"     # 一路回车
pbcopy < ~/.ssh/id_ed25519.pub          # 复制公钥
# 打开 https://github.com/settings/keys → New SSH key → 粘贴 → 保存
ssh -T git@github.com                   # 看到 "Hi oillx!" 就通了
```

> 如果 `ssh -T` 卡住不返回，多半是 22 端口被网络屏蔽。改用 443 端口：
> ```bash
> cat >> ~/.ssh/config <<'EOF'
> Host github.com
>   HostName ssh.github.com
>   Port 443
>   User git
> EOF
> ```

---

## 方案 B：从压缩包开始

1. 下载 `袋袋集_iOS工程.zip` 并解压
2. 按方案 A 的步骤操作（把 `<你的项目目录>` 换成解压后的 `DaiDaiJi` 目录）

---

## 方案 C：改用 HTTPS（不想配 SSH 时）

```bash
git remote add origin https://github.com/oillx/DaiDaiJi.git
git push -u origin main
# 提示用户名时填 oillx，密码填 Personal Access Token
# （不是账号密码！在 https://github.com/settings/tokens 生成，勾选 repo 权限）
```

---

## 推完之后：在 Xcode 里编译

```bash
cd <项目目录>
git pull
open DaiDaiJi.xcodeproj        # 或直接双击
```

Xcode 里只需做一次设置：

1. 左侧选中 **DaiDaiJi** 项目 → **TARGETS → DaiDaiJi** → **Signing & Capabilities**
2. **Team** 选你的 Apple ID（没有就点 `Add an Account`）
3. 若报 `Bundle Identifier is not available`，把 `com.daidaiji.app` 改成 `com.<你的名字>.daidaiji`
4. 顶部设备选一个 iPhone 模拟器 → 按 **⌘R**

**Team 和 Bundle ID 是每台机器私有的，不会跟着仓库走**——所以别人 clone 下来也要各自设一次，这是正常的。

---

## 关于 .gitignore

工程里已带 `.gitignore`，会忽略：

- `xcuserdata/`（Xcode 的个人窗口状态，不该进仓库）
- `DerivedData/`、`.build/`（编译产物）
- `.DS_Store`（macOS 目录元数据）

不会忽略（必须进仓库）：

- `DaiDaiJi.xcodeproj/`（工程文件本体）
- `xcshareddata/xcschemes/`（**共享 scheme**，缺了它别人 clone 下来没有 ▶️ 按钮）
- `Assets.xcassets/`（图片资源）
- `project.yml`（XcodeGen 描述文件，可选）

---

## 可选：用 XcodeGen 重新生成工程

手改 `.pbxproj` 容易出错。如果以后加了新文件，推荐用 XcodeGen 重生成：

```bash
brew install xcodegen
cd DaiDaiJi
xcodegen generate
```

它会根据 `project.yml` 自动扫描目录下所有 `.swift` 文件，不用手动登记。
