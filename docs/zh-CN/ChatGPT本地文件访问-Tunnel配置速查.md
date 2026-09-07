# ChatGPT 本地文件访问：Tunnel 配置速查

> 适合已经了解基本原理、只想快速完成配置的人。第一次接触 MCP 或 Tunnel，请先读[零基础教程](./ChatGPT本地文件访问-零基础教程.md)。文中全部路径和编号均为占位符。

## 链路

```text
ChatGPT → OpenAI Tunnel → 本机 tunnel-client → Local Ops MCP → 指定工作区
```

Local Ops 必须在服务端限制工作区，不能仅靠聊天提示词限制访问范围。

## 准备

- Windows、PowerShell 和 Node.js；
- Local Ops MCP 仓库；
- 一个明确的本地项目目录；
- 具备开发者模式资格的 ChatGPT 账户；
- OpenAI Platform 创建的 Tunnel ID；
- Runtime API Key；
- 网络需要代理时，代理软件提供的 HTTP 或 Mixed 端口。

根据 [OpenAI 官方开发者模式文档](https://developers.openai.com/api/docs/guides/developer-mode)，ChatGPT 开发者模式目前在网页版向 Pro、Plus、Business、Enterprise 和 Education 账户开放；免费账户不在官方列出的适用范围内。ChatGPT 套餐权限与 OpenAI Platform 的 API/Tunnel 权限是两套独立条件。

Runtime API Key 必须保密，不要写入文档、配置文件、源码、聊天、截图或 Git。

## 填写本地配置

复制模板：

```powershell
Copy-Item .\config\local-ops.example.psd1 .\config\local-ops.psd1
```

编辑 `config/local-ops.psd1`：

```powershell
@{
    WorkspaceRoot = 'D:\Projects\MyProject'
    TunnelId     = 'tunnel_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    ProxyUrl     = 'http://127.0.0.1:<PROXY_PORT>'
    Profile      = 'local-ops'
    NodePath     = ''
}
```

不需要代理时将 `ProxyUrl` 留空。`NodePath` 通常也留空，让脚本自动检测。真实配置应由 Git 忽略。

## 初始化一次

在仓库根目录双击：

```text
Local-Ops.bat → 3. Reinitialize configuration
```

也可以在 PowerShell 中运行：

```powershell
.\scripts\setup-tunnel.ps1
```

出现 `Runtime API key:` 时粘贴密钥并按 Enter。安全输入不显示字符或星号是正常现象。

## 日常启动

双击：

```text
Local-Ops.bat → 2. Start Tunnel
```

或运行：

```powershell
.\scripts\run-tunnel.ps1
```

看到下面两类日志说明本机链路已启动：

```text
tunnel metadata fetched
tunnel-client started
```

使用期间保持窗口开启；按 `Ctrl+C` 可停止。

## 在 ChatGPT 中完成连接

先在 OpenAI Platform 的 Tunnel 编辑页面确认 `ChatGPT workspaces` 已选择当前使用插件的工作区并保存。然后在 ChatGPT 开发者模式创建 Tunnel 连接的应用，从“可用隧道”列表选择对应 Tunnel。Local Ops 当前未实现 OAuth，因此身份验证选择“无身份验证”；Runtime API Key 只在本机 tunnel-client 中输入，不填入插件表单。

如果“可用隧道”显示“暂无隧道”，先检查 Tunnel 的 `ChatGPT workspaces`，保存后刷新 ChatGPT 插件页面再重试。Tunnel ID 仍用于本机 `tunnel-client` 初始化；ChatGPT 既可能列出可用 Tunnel，也支持手动粘贴有效的 Tunnel ID。

请区分四个状态：

```text
创建插件 → 安装插件 → 连接插件 → 在当前消息中选择插件
```

本机 Tunnel 在线并不等于当前对话已经选中插件。

## 只读验证

新建对话，选择插件后发送：

```text
使用 Local Ops 列出工作区根目录，只读取，不要修改。
```

必须真正返回本地目录内容才算成功，仅回复“可以访问”不算。

## 快速排错

| 现象 | 优先检查 |
|---|---|
| Node.js 路径被截断 | 路径是否含空格；必要时设置无空格的 `NodePath` |
| MCP probe 失败 | Local Ops 服务与工作区路径 |
| Tunnel metadata 获取失败 | Runtime API Key、代理和 `api.openai.com` 网络 |
| “可用隧道”显示“暂无隧道” | 在 OpenAI Platform 编辑 Tunnel，为其选择当前 ChatGPT workspace，保存后刷新插件页面 |
| 插件旁仍有“＋” | 插件尚未安装 |
| 详情页仍显示“连接” | 保持 Tunnel 在线后点击连接 |
| 当前对话没有工具 | 新建对话并在发送消息时选择插件 |
| 新增、删除或开关隐藏的工具没有正确显示 | 重启 Tunnel 后，先在连接器详情页刷新应用；若实测仍未更新，再删除旧连接器定义并用原 Tunnel ID 创建 |
| 能看到旧聊天内容但读不到新文件 | Tunnel 已停止或电脑休眠 |

## 配置项从哪里来

| 配置项 | 从哪里得到 | 忘了怎么办 | 修改后 |
|---|---|---|---|
| `WorkspaceRoot` | 自己选择的本地项目文件夹 | 在资源管理器地址栏复制完整路径 | 重新初始化 |
| `TunnelId` | OpenAI Platform 的 Tunnels 页面 | 回页面查看 `ID` 列 | 必须重新初始化 |
| `ProxyUrl` | 代理软件的 HTTP/Mixed 端口 | 打开代理软件查看本地端口 | 建议重新初始化并运行 doctor |
| `Profile` | 自己起的本机配置昵称 | 不确定时用 `local-ops` | 必须重新初始化 |
| `NodePath` | Node.js 可执行文件路径 | 通常留空自动检测 | 重新初始化 |
| Runtime API Key | OpenAI Platform 的 Runtime API Keys 页面 | 旧值通常不可找回，应新建并撤销旧密钥 | 在脚本提示时输入，不写入配置 |

### WorkspaceRoot

它决定 Local Ops 能访问哪个目录。请选择一个真实、明确的项目路径，例如 `D:\Projects\MyProject`，不要设为整个磁盘、用户主目录或系统目录。

### TunnelId

创建 Tunnel 后由 OpenAI 自动生成，形式为 `tunnel_...`。应复制 `ID` 列的完整值，不要复制名称，也不要把 Runtime API Key 当成 Tunnel ID。

### ProxyUrl

浏览器能联网不代表 tunnel-client 自动使用相同代理。在代理软件中查找 `HTTP Port`、`Mixed Port`、混合端口或本地端口；无需代理时留空。

### Profile 与 NodePath

`Profile` 只是本机配置昵称，只有一套配置时使用 `local-ops` 即可。`NodePath` 通常留空；自动检测失败时，可填写不含空格的 Node.js 可执行文件路径。

### Runtime API Key

它不属于 `local-ops.psd1`。旧值通常无法再次查看；遗失时应新建密钥，并撤销不再使用的旧密钥。不要保存到 BAT、`.env`、聊天、截图或 Git。

## 什么时候需要重新初始化

最简单的判断是：

```text
配置没改：只启动
配置改了：重新初始化，成功后再启动
看不懂 Profile 或 configuration 错误：重新初始化
```

以下情况通常只需双击 `Local-Ops.bat` 并选择 `2. Start Tunnel`：

- 电脑或 ChatGPT 客户端刚重启；
- 昨天停止了 Tunnel，今天继续用；
- Tunnel 窗口被关闭；
- 代理重新连接，但端口没变；
- Tunnel 暂时离线，但本地配置没变。

以下情况需要双击 `Local-Ops.bat` 并选择 `3. Reinitialize configuration`，成功后再启动：

- 第一次使用，尚未成功初始化；
- `TunnelId`、`Profile`、`WorkspaceRoot`、`ProxyUrl` 或 `NodePath` 改变；
- 启动时报 `profile not found`、`configuration invalid`、`doctor failed` 或 `init required`；
- 换电脑、重建本地配置，或 tunnel-client 的本机 Profile 丢失。

重新初始化向导会显示当前工作区、Tunnel ID、代理端口和 Profile；按 Enter 保留当前值，输入新值即可更新。它用于保存修改、创建或更新 Profile 并执行检查，不代替日常启动。

下面几种情况不是本机初始化问题：

- ChatGPT 仍显示旧工具，或开关关闭后网页仍显示该工具：服务端策略在 Tunnel 重启后已经生效；先在连接器详情页刷新应用。若实测仍未更新，再删除旧连接器定义并用原 Tunnel ID 重新创建；
- 应用显示“未安装”或“未连接”：需要在 ChatGPT 中完成安装和连接；
- 当前对话没有工具：新建对话，并在发送消息时选择正确应用。

## 将本机配置放在代码目录之外

`launcher.ps1`、`first-time-setup.ps1`、`setup-tunnel.ps1` 和 `run-tunnel.ps1` 都接受 `-ConfigPath`。适合将公开代码作为子模块使用、私人配置留在外层目录的情况：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\launcher.ps1 -ConfigPath ..\private-config\local-ops.psd1
```

菜单会把选定的配置路径传给首次配置、启动和重新初始化操作；首次配置向导会在该位置读取或创建配置。路径可以包含空格，命令行中需用引号包围。未指定参数时仍使用代码目录下的 `config/local-ops.psd1`。真实配置和 Runtime API Key 不应提交到公开仓库。

维护者可运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-config-path.ps1` 验证路径传递；此测试使用模拟 Tunnel，不需要凭据。

## 启动前选择配置

给 launcher.ps1 加上 `-SelectConfig`，会先列出 `-ConfigPath` 所在目录中的 `.psd1` 文件（不递归，排除 `*.example.psd1` 模板）。例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\launcher.ps1 -ConfigPath ..\private-config\local-ops.psd1 -SelectConfig
```

输入编号选择文件，回车使用 ConfigPath 指定的默认文件，Q 退出。配置列表只展示文件名，不读取或打印其中的凭据。没有配置时直接进入操作菜单，可用首次配置创建默认文件。菜单显示当前选中的完整路径；首次配置、启动和重新初始化都使用该路径。不加 SelectConfig 时保留原来的固定路径行为。

可以在私人配置目录准备 `work.psd1`、`personal.psd1` 等文件，分别填写 WorkspaceRoot。再次打开菜单即可重新选择；不会记住或自动覆盖默认配置。切换前先关闭之前的 Tunnel 窗口，菜单不会停止已有进程。若使用不同 TunnelId，请为每个 Tunnel 使用独立 Profile，并先用所选配置执行重新初始化；单纯选择文件不会重建 Tunnel profile。

配置选择测试：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-config-selection.ps1`，不需要真实凭据或 Tunnel。

配置向导编辑已有文件时，会保留未修改字段、Git 权限开关和注释；每次覆盖前在原文件旁创建唯一命名的 `.bak` 备份。代理输入回车保留原值，输入 `none` 清空。`first-time-setup.ps1 -EditOnly -ConfigPath <配置文件>` 只编辑，不调用 Tunnel 初始化。配置文件无效时停止，不覆盖原文件。
