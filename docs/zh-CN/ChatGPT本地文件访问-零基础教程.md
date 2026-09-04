# 从零开始：让 ChatGPT 安全读写本地项目

> 文中的 Tunnel ID、用户名、项目路径和代理端口均为占位符，请替换成自己的配置。绝对不要公开 Runtime API Key。

## 一、为什么需要 Local Ops

普通 ChatGPT 运行在 OpenAI 的服务器上，并不在你的电脑里。因此，即使你在对话里写：

```text
请读取 D:\Projects\MyProject\README.md
```

ChatGPT 默认也看不到这个文件。

常见工作方式是先在 ChatGPT 中讨论，再把结论复制给本地编码工具执行。为了减少来回复制，可以搭建一条权限受限的工具链：

```text
ChatGPT
   ↓
OpenAI Tunnel
   ↓
本机 tunnel-client
   ↓
Local Ops MCP
   ↓
指定项目目录
```

完成后，ChatGPT 可以调用 Local Ops 提供的文件工具，但只能访问你明确授权的工作区。

## 二、四个核心概念

### ChatGPT

负责理解需求、思考并决定是否调用工具。它不会因为看到一个本地路径就自动获得文件权限。

### MCP

MCP 可以理解为 AI 与工具之间的统一接口。Local Ops MCP 可以提供列出目录、读取文本和写入文本等能力。

### Tunnel

Tunnel 是 OpenAI 与本机 MCP 之间的私有通道。本机主动连接 OpenAI，因此不需要直接把本地服务暴露到公网。

### Runtime API Key

Runtime API Key 是 tunnel-client 连接 OpenAI Tunnel 服务时使用的凭据，相当于工作证。

它必须保密：

- 不要发进聊天；
- 不要放进截图；
- 不要写入 Markdown；
- 不要提交到 Git；
- 不要填写到 ChatGPT 插件表单。

## 三、安全边界

示例工作区：

```text
D:\Projects\MyProject
```

Local Ops 应只允许访问这个目录及其子目录，不要为了方便把根目录设置成：

```text
C:\
D:\
C:\Users
用户主目录
```

最稳妥的原则是：一个 Local Ops 服务只对应一个明确的项目目录。

## 四、准备工作

### 先确认 ChatGPT 开发者模式资格

本方案的 ChatGPT Hosted Chat 接入依赖 **ChatGPT 开发者模式**。根据 [OpenAI 官方开发者模式文档](https://developers.openai.com/api/docs/guides/developer-mode)，该功能目前在网页版向 Pro、Plus、Business、Enterprise 和 Education 账户开放；免费账户不在官方列出的适用范围内。请先确认可以在“设置 → 安全与登录”中启用开发者模式，再继续配置 Tunnel。

ChatGPT 套餐权限与 OpenAI Platform 的 API/Tunnel 权限彼此独立：拥有 Runtime API Key 不代表 ChatGPT 账户自动拥有开发者模式，拥有开发者模式也不代表 Platform 侧已经具备 Tunnel 和 Runtime API Key。

你需要：

1. Windows 电脑；
2. 具备开发者模式资格的 ChatGPT 账号，以及具备 Tunnel 权限的 OpenAI Platform 账号；
3. PowerShell；
4. Node.js；
5. Local Ops MCP 项目；
6. 一个准备授权的本地项目目录；
7. OpenAI Runtime API Key；
8. 如果网络无法直连 OpenAI，还需要本地代理的 HTTP 或 Mixed 端口。

本文使用以下占位符：

```text
<LOCAL_OPS_DIR>   Local Ops 工具目录，例如 C:\Tools\local-ops-mcp
<WORKSPACE_DIR>   授权项目目录，例如 D:\Projects\MyProject
<TUNNEL_ID>       OpenAI Platform 生成的 Tunnel ID
<PROXY_PORT>      本地代理的 HTTP 或 Mixed 端口
```

## 五、创建 OpenAI Tunnel

在 OpenAI Platform 的 Tunnels 管理页面创建 Tunnel。

示例：

```text
Name: Local Ops - MyProject
Description: Private tunnel for a scoped local workspace
```

创建或编辑 Tunnel 时，在 `ChatGPT workspaces` 中选择之后实际使用插件的 ChatGPT 工作区，然后保存。`Organizations` 与 `ChatGPT workspaces` 分别控制 Platform 组织范围和 ChatGPT 侧的可见范围；如果没有关联正确的 ChatGPT 工作区，Tunnel 即使已经创建并由本机成功连接，也不会出现在 ChatGPT 的“可用隧道”列表中。

创建后记录 `ID` 列中的完整 Tunnel ID，形式类似：

```text
tunnel_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Tunnel ID 是基础设施标识，不等于密钥。公开教程中仍建议使用占位符，不发布真实值。

## 六、创建 Runtime API Key

进入 OpenAI Platform 的 Runtime API Keys 页面创建密钥。

密钥一般只完整显示一次。创建后应保存到可信的密码管理工具。如果密钥意外出现在公开内容中，应立即撤销并重新创建。

## 七、准备 Local Ops MCP

一个最小的 Local Ops 项目通常包含：

```text
<LOCAL_OPS_DIR>
├── server.mjs
├── scripts
│   ├── setup-tunnel.ps1
│   └── run-tunnel.ps1
└── bin
    └── tunnel-client.exe
```

服务端必须校验所有文件路径都位于 `<WORKSPACE_DIR>` 内。不要只靠提示词限制权限。

## 八、创建本地配置文件

先复制脱敏示例：

```powershell
Copy-Item .\config\local-ops.example.psd1 .\config\local-ops.psd1
```

编辑 `config/local-ops.psd1`：

```powershell
@{
    WorkspaceRoot = '<WORKSPACE_DIR>'
    TunnelId     = '<TUNNEL_ID>'
    ProxyUrl     = 'http://127.0.0.1:<PROXY_PORT>'
    Profile      = 'local-ops'
}
```

真实配置应由 `.gitignore` 排除。不要在里面保存 Runtime API Key。

## 九、第一次初始化

打开 PowerShell，进入 Local Ops 目录：

```powershell
cd <LOCAL_OPS_DIR>
```

例如：

```powershell
cd C:\Tools\local-ops-mcp
```

运行初始化脚本：

```powershell
.\scripts\setup-tunnel.ps1
```

出现下面的提示时，粘贴 Runtime API Key 并按 Enter：

```text
Runtime API key:
```

安全输入不会显示字符或星号，这是正常现象。

初始化脚本通常负责：

1. 检查工作区是否存在；
2. 定位 `server.mjs` 和 Node.js；
3. 创建 tunnel-client profile；
4. 设置代理；
5. 运行 doctor 检查。

## 十、代理配置

浏览器能访问 ChatGPT，不代表 tunnel-client 会自动继承浏览器代理。

如果 tunnel-client 直连 `api.openai.com` 超时，可以设置：

```powershell
$env:TUNNEL_CLIENT_HTTP_PROXY = 'http://127.0.0.1:<PROXY_PORT>'
$env:CONTROL_PLANE_HTTP_PROXY = 'http://127.0.0.1:<PROXY_PORT>'
```

将 `<PROXY_PORT>` 替换为代理软件显示的 HTTP 或 Mixed 端口。

不要照抄别人电脑的端口。每台电脑的代理配置可能不同。

## 十一、启动 Tunnel

执行：

```powershell
.\scripts\run-tunnel.ps1
```

成功日志通常包含：

```text
local-ops-mcp root: <WORKSPACE_DIR>
tunnel metadata fetched
tunnel-client started
```

运行 Tunnel 时必须保持 PowerShell 窗口开启。

## 十二、在 ChatGPT 创建 Tunnel 连接的应用

建议先使用 ChatGPT 网页端完成创建。界面会演进，以下以当前官方流程为准：

1. 打开 ChatGPT；
2. 在“设置 → 安全与登录”启用开发者模式；
3. 打开 ChatGPT 的 Plugins 页面，点击加号创建开发者模式应用；
4. 连接方式选择“隧道”，并从“可用隧道”列表选择对应 Tunnel；也可在需要时粘贴有效的 Tunnel ID。

示例填写：

```text
名称：Local Ops
描述：读取和写入指定本地项目中的文件
连接：隧道
可用隧道：Local Ops - MyProject
身份验证：无身份验证
```

勾选风险确认后创建。

为什么选择“无身份验证”？Local Ops 当前的本地 stdio MCP 服务未实现 OAuth；Tunnel 与 OpenAI 之间的传输身份由本机 Runtime API Key 负责。这是本项目的配置选择，不代表 Secure MCP Tunnel 不支持 OAuth。

## 十三、验证读取能力

新建 ChatGPT 对话，选择刚创建的 Local Ops，发送：

```text
使用 Local Ops 列出工作区根目录，只读取，不要修改。
```

成功时应看到真实的目录和文件列表，并显示工具调用记录。

仅仅得到“我可以读取”的文字回复不算成功，必须真的返回本地目录内容。

## 十四、让桌面客户端同步插件

如果桌面客户端曾安装同名的本地 STDIO MCP，可能与 Tunnel 连接的应用冲突。

可以这样处理：

1. 打开桌面客户端“设置 → 插件 → MCP”；
2. 暂时关闭服务器列表中的本地 `local-ops`；
3. 完全退出桌面客户端，包括系统托盘；
4. 保持 tunnel-client 运行；
5. 重新打开桌面客户端；
6. 切换到 ChatGPT；
7. 新建对话；
8. 选择从账号同步的 Tunnel 版 Local Ops；
9. 再次执行只读目录测试。

不要沿用创建插件之前的旧对话，因为旧会话可能缓存了当时的工具清单。

## 十五、日常启动和停止

每次使用前：

1. 启动代理软件；
2. 确认代理端口没有变化；
3. 打开 PowerShell；
4. 运行：

```powershell
cd <LOCAL_OPS_DIR>
.\scripts\run-tunnel.ps1
```

使用完成后，在 PowerShell 中按：

```text
Ctrl+C
```

停止后，ChatGPT 无法读取新文件、检查最新状态或执行写入，但已经出现在聊天中的内容仍保留在对话上下文中。

停止 Tunnel 不会删除插件或配置。下次重新运行脚本即可恢复。

## 十六、重新初始化和排错

平时只需启动 Tunnel。只有本机配置发生变化、Profile 丢失或诊断明确报错时才需要重新初始化；ChatGPT 侧的插件安装、工具清单缓存和“可用隧道”列表问题不能通过反复初始化本机来修复。

这些判断和错误处理统一维护在 [Tunnel 配置速查的“什么时候需要重新初始化”](./ChatGPT本地文件访问-Tunnel配置速查.md#什么时候需要重新初始化)与[“快速排错”](./ChatGPT本地文件访问-Tunnel配置速查.md#快速排错)中。

## 十七、常见错误

### 1. Node.js 路径被截断

如果路径包含空格，例如：

```text
C:\Program Files\nodejs\node.exe
```

某些 Windows 命令解析可能把它拆坏。可以改用不含空格的 Node.js 路径，并将反斜杠转换为正斜杠：

```text
C:/Tools/node/node.exe
C:/Tools/local-ops-mcp/server.mjs
```

### 2. 能提及 Local Ops，但不能调用

可能选择了本地 `personal` STDIO 插件，而不是 Tunnel 版应用。需要在 ChatGPT 开发者模式中创建 Tunnel 连接的应用，并在新对话里选择它。

### 3. “可用隧道”显示“暂无隧道”

在 OpenAI Platform 编辑该 Tunnel，在 `ChatGPT workspaces` 中选择当前使用插件的工作区并保存。然后刷新 ChatGPT 插件页面，重新打开创建表单；同时确认 Platform 与 ChatGPT 使用的是预期账号、组织和工作区。

### 4. 创建插件时出错

如果本地 MCP 健康，但 Tunnel 元数据获取失败，重点检查：

- Runtime API Key；
- Tunnel ID；
- OpenAI 账号或组织是否一致；
- `api.openai.com` 网络连接；
- tunnel-client 是否使用了正确代理。

### 5. 网页可用，桌面客户端不可用

关闭同名本地 MCP，完全重启客户端，并创建新对话。桌面客户端可能需要重新同步插件目录和工具清单。

## 十八、第一次写入怎么测试

读取成功后，不要立刻修改重要文件。可以先创建一个临时测试文件：

```text
使用 Local Ops 在工作区根目录创建 local-ops-test.txt，内容为“Local Ops write test”。写入前先告诉我完整路径，并等待确认。
```

测试完成后再删除它。

修改重要项目时，推荐流程是：

1. 先读取原文件；
2. 说明修改计划；
3. 等待用户确认；
4. 执行写入；
5. 汇报变化；
6. 使用 Git 检查差异。

## 十九、安全清单

- [ ] Local Ops 只允许访问一个明确的项目目录；
- [ ] Runtime API Key 没有进入聊天、文档、截图或 Git；
- [ ] 第一个请求只读取目录；
- [ ] 写入前明确目标文件和改动；
- [ ] 重要项目使用 Git；
- [ ] 不使用时停止 Tunnel；
- [ ] 分享教程前替换真实 Tunnel ID、用户名、路径和代理端口。

## 二十、工作原理总结

这个方案不是把整台电脑的最高权限交给 ChatGPT，而是：

```text
运行一个权限受限的本地文件工具
          ↓
工具只允许访问指定工作区
          ↓
Tunnel 临时将工具接入 ChatGPT
          ↓
用户可以随时通过 Ctrl+C 断开
```

合理配置后，网页端和桌面客户端可以使用同一个 Tunnel 连接的应用：

```text
网页 ChatGPT ─┐
              ├→ OpenAI Tunnel → Local Ops MCP → 指定项目目录
桌面 ChatGPT ─┘
```

它减少了在 ChatGPT 与本地执行工具之间搬运内容的成本，同时保留了明确、可停止、可审查的权限边界。

---

## 分享前提醒

公开发布自己的实践记录前，至少搜索并删除：

```text
真实 Runtime API Key
真实 Tunnel ID
OpenAI 组织或 Workspace ID
Windows 用户名
私人项目名称
真实绝对路径
不希望公开的代理配置
邮箱、账号截图和浏览器标签信息
```

本文已经使用占位符，不包含作者个人配置。
