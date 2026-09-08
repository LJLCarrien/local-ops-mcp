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
| `WorkspaceRoot` | 自己选择的本地项目文件夹 | 在资源管理器地址栏复制完整路径 | 关闭旧 Tunnel 后重新启动 |
| `TunnelId` | OpenAI Platform 的 Tunnels 页面 | 回页面查看 `ID` 列 | 更换独立 Profile 并初始化 |
| `ProxyUrl` | 代理软件的 HTTP/Mixed 端口 | 打开代理软件查看本地端口 | 重新启动 |
| `Profile` | 自己起的本机配置昵称 | 使用向导建议的独立名称 | 新 Profile 需初始化 |
| `NodePath` | Node.js 可执行文件路径 | 通常留空自动检测 | 重新初始化 |
| Runtime API Key | OpenAI Platform 的 Runtime API Keys 页面 | 旧值通常不可找回，应新建并撤销旧密钥 | 在脚本提示时输入，不写入配置 |

### WorkspaceRoot

它决定 Local Ops 能访问哪个目录。请选择一个真实、明确的项目路径，例如 `D:\Projects\MyProject`，不要设为整个磁盘、用户主目录或系统目录。

### TunnelId

创建 Tunnel 后由 OpenAI 自动生成，形式为 `tunnel_...`。应复制 `ID` 列的完整值，不要复制名称，也不要把 Runtime API Key 当成 Tunnel ID。

### ProxyUrl

浏览器能联网不代表 tunnel-client 自动使用相同代理。在代理软件中查找 `HTTP Port`、`Mixed Port`、混合端口或本地端口；无需代理时留空。

### Profile 与 NodePath

`Profile` 是本机 Tunnel 配置名称。向导根据配置文件名和 Tunnel ID 生成独立默认名；不同 Tunnel 不要共用同一个 Profile。`NodePath` 通常留空；自动检测失败时，可填写不含空格的 Node.js 可执行文件路径。

### Runtime API Key

它不属于 `local-ops.psd1`。旧值通常无法再次查看；遗失时应新建密钥，并撤销不再使用的旧密钥。不要保存到 BAT、`.env`、聊天、截图或 Git。

## 什么时候需要重新初始化

菜单中的三个操作已分开：

- `1. Create or edit configuration`：新建或编辑所选配置；不连接 Tunnel。保留未编辑字段、Git 权限和注释，覆盖前自动保存 `.bak` 备份。
- `2. Start Tunnel`：先核对 Profile 与所选 TunnelId 的绑定。匹配才启动；缺少 Profile 时询问是否初始化，可取消。
- `3. Initialize Tunnel`：只读取所选配置，创建或检查 Tunnel profile，不改写私人配置。已有匹配的 profile 会先备份；不覆盖绑定到其他 Tunnel 的 profile。

只有新 Profile、Profile 丢失、更换 NodePath 或服务脚本位置等情况需要初始化。同一 Tunnel 只修改 WorkspaceRoot、代理或 Git 权限时，关闭旧 Tunnel 后重新启动即可。更换 TunnelId 时，编辑配置使用新的独立 Profile，再初始化一次。后续选配置即可启动。

如果列表显示 Conflict（其他配置用相同 Profile 绑定不同 Tunnel）或 Mismatch（已安装 Profile 绑定另一个 Tunnel），先用操作 1 编辑。向导会建议独立名称；回车接受后，再执行操作 3。不会自动覆盖另一个 Tunnel 的绑定。

旧命令 `first-time-setup.ps1 -Reinitialize -ConfigPath <文件>` 现在也只初始化，不进入编辑问答；`-EditOnly` 只编辑。不带这两个开关直接运行该脚本时，仍支持首次安装的编辑、初始化和可选启动流程。

下面几种情况不是本机初始化问题：

- ChatGPT 仍显示旧工具，或开关关闭后网页仍显示该工具：服务端策略在 Tunnel 重启后已经生效；先在连接器详情页刷新应用。若实测仍未更新，再删除旧连接器定义并用原 Tunnel ID 重新创建；
- 应用显示“未安装”或“未连接”：需要在 ChatGPT 中完成安装和连接；
- 当前对话没有工具：新建对话，并在发送消息时选择正确应用。

## 将本机配置放在代码目录之外

`launcher.ps1`、`first-time-setup.ps1`、`setup-tunnel.ps1` 和 `run-tunnel.ps1` 都接受 `-ConfigPath`。适合将公开代码作为子模块使用、私人配置留在外层目录的情况：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\launcher.ps1 -ConfigPath ..\private-config\local-ops.psd1
```

菜单把选定路径传给编辑、启动和初始化操作；编辑向导在该位置读取或创建配置。路径可以包含空格，命令行中需用引号包围。未指定参数时仍使用代码目录下的 `config/local-ops.psd1`。真实配置和 Runtime API Key 不应提交到公开仓库。

维护者可运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-config-path.ps1` 验证路径传递；此测试使用模拟 Tunnel，不需要凭据。

## 启动前选择配置

给 launcher.ps1 加上 `-SelectConfig`，会先列出 ConfigPath 所在目录中的 `.psd1` 文件（不递归，排除 `*.example.psd1`）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\launcher.ps1 -ConfigPath ..\private-config\local-ops.psd1 -SelectConfig
```

输入编号选择，回车选择默认文件，Q 退出，N 输入新配置文件名。列表显示文件名、工作区、Profile 和检查状态，不打印 Tunnel ID 或凭据。新建文件要在随后操作菜单选择 1 编辑并保存；同名文件不会被新建操作覆盖。

| 状态 | 含义与操作 |
|---|---|
| Ready | 本机绑定已匹配，可以选择启动；不表示网络已经在线 |
| Missing | 需要初始化；启动时会询问是否执行 |
| Conflict / Mismatch | 先编辑并选择独立 Profile，再初始化 |
| Invalid | 配置语法、工作区或必要字段有误，先修正 |
| Unknown | 无法可靠检查，不启动；检查客户端是否支持 profiles list --json、profile 文件格式和环境覆盖 |

绑定检查只接受官方 init 通常生成的简单字面量 YAML；自定义别名、合并、重复字段等无法可靠判断时显示 Unknown。启用了 TUNNEL_CLIENT_CONFIG 或 TUNNEL_CLIENT_PROFILE_FILE 环境覆盖时，也会提示先清除覆盖，避免检查和运行使用不同文件。启动及 doctor 命令显式传递已核对的 profile 文件和 Tunnel ID。

可以准备 work.psd1、personal.psd1 等私人配置，每份填写各自的 WorkspaceRoot。菜单不会记住或覆盖默认选择，也不会停止已有进程；切换前先关闭旧 Tunnel 窗口。不加 SelectConfig 则直接使用 ConfigPath 指定的文件。

编辑时代理输入回车保留现值，输入 none 清空。无效配置不会被覆盖。备份保存在原文件旁，文件名带时间和随机后缀并以 .bak 结尾；配置目录中的真实 psd1 文件和备份均被 Git 忽略，公开模板除外。

维护者验证（模拟客户端，不连接真实 Tunnel）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-config-path.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-config-selection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-profile-state.ps1
```
