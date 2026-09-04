# Local Ops MCP

一个轻量、零运行时依赖的本地 MCP 服务。它允许 ChatGPT 或 Codex 在一个明确授权的工作区内管理文件和本地 Git 仓库，同时由服务端阻止路径越界。

> 本项目是个人参考实现，不是 OpenAI 官方产品，也没有经过独立的专业安全审计。请勿直接用于生产环境或关键数据；使用者负责限制工作区权限、备份数据、保护凭据并审查写入与远程 Git 操作。

```text
ChatGPT / Codex
       ↓ MCP
Local Ops MCP
       ↓ 路径边界检查
指定的本地项目目录
```

## 文档

第一次使用，建议从[中文文档导航](./docs/zh-CN/README.md)开始：

- [零基础完整教程](./docs/zh-CN/ChatGPT本地文件访问-零基础教程.md)：理解 MCP、Tunnel、安全边界和完整搭建流程；
- [Tunnel 综合配置速查](./docs/zh-CN/ChatGPT本地文件访问-Tunnel配置速查.md)：查询配置来源、日常启动、重新初始化和故障定位；
- [换电脑只看这一页](./docs/zh-CN/换电脑只看这一页.md)：在新电脑上恢复配置；
- [全部文档目录](./docs/README.md)：查看公开文档。
- [文档维护地图](./docs/MAINTENANCE.md)：了解每类信息的唯一维护位置。

公开文档只使用占位路径和示例编号。发布截图或日志前，仍需检查 Runtime API Key、真实 Tunnel ID、本机用户名和私人项目路径。

## 环境要求

- Node.js 20 或更高版本
- 使用 ChatGPT 或 Codex；其他客户端尚未在本项目中验证
- 使用 Hosted Chat 时需要 OpenAI Secure MCP Tunnel 与官方 `tunnel-client`

使用 ChatGPT Hosted Chat 接入时还需要 **ChatGPT 开发者模式**。根据 [OpenAI 官方开发者模式文档](https://developers.openai.com/api/docs/guides/developer-mode)，该功能目前在网页版向 Pro、Plus、Business、Enterprise 和 Education 账户开放；免费账户不在官方列出的适用范围内。开始配置前，请先确认自己的账户能够在“设置 → 安全与登录”中启用开发者模式。ChatGPT 套餐权限与 OpenAI Platform 的 API/Tunnel 权限是两套独立条件，具备其中一项不代表自动具备另一项。

## 可用工具

- 浏览：`list_directory`、`read_file`
- 写入：`write_file`、`create_directory`
- 整理：`copy_file`、`move_file`、`rename_file`
- 删除：`delete_file`、`delete_directory`

## 测试

```powershell
npm test
```

## Git 支持

Git 必须已经安装并位于 `PATH`。仓库路径使用工作区相对路径，解析后的仓库必须位于 `LOCAL_OPS_ROOT` 下。

`git_add` 必须传入明确的仓库相对路径列表，`git_commit` 只提交已经暂存的修改。`git_amend_message` 只修改最近一次本地提交的信息，不会把暂存区或工作区修改并入该提交；它会改写最近一次提交，应仅在确认尚未推送或明确需要改写历史时使用。不开放 checkout、reset、删除分支、强制推送、删除远程分支、任意 Git 参数或通用 Shell。

远程工具使用仓库中已有的 remote，以及电脑现有的 Git Credential Manager 或 SSH 凭据，不接受凭据作为工具输入。`git_pull` 始终使用 `--ff-only`；`git_push` 只把 `HEAD` 通过非强制 refspec 推送到当前分支的 upstream。允许网络 URL 和 `LOCAL_OPS_ROOT` 内的本地 remote，拒绝根目录之外的本地 remote。

本地 Git 命令默认超时 30 秒，远程命令默认超时 60 秒。可通过 `LOCAL_OPS_GIT_TIMEOUT_MS` 和 `LOCAL_OPS_GIT_REMOTE_TIMEOUT_MS` 调整；命令输出与文件读取共同遵守 `LOCAL_OPS_MAX_BYTES` 上限。

### Git 开关

| 环境变量 | 默认值 | 控制范围 |
| --- | --- | --- |
| `LOCAL_OPS_GIT_READ` | `true` | status、diff、log、show、branch |
| `LOCAL_OPS_GIT_WRITE` | `true` | add、commit、amend message |
| `LOCAL_OPS_GIT_REMOTE` | `false` | 所有远程工具的总开关 |
| `LOCAL_OPS_GIT_FETCH` | `true` | 总开关启用后的 fetch |
| `LOCAL_OPS_GIT_PULL` | `false` | 总开关启用后的仅快进 pull |
| `LOCAL_OPS_GIT_PUSH` | `false` | 总开关启用后的当前分支 push |

关闭的工具不会出现在 MCP `tools/list` 中，直接调用也会被拒绝。布尔值支持 `true`/`false`、`1`/`0`、`yes`/`no` 或 `on`/`off`。

修改开关后，先重启 Local Ops Tunnel；服务端安全策略会立即生效。若工具增减后 ChatGPT 仍显示旧清单，先在连接器详情页刷新应用以重新拉取工具描述和清单；若当前界面没有刷新入口或刷新后实测仍未更新，再删除旧的 Local Ops 自定义连接器，并保持原 Tunnel 运行、使用原 Tunnel ID 重新创建。后者是本项目的故障兜底经验，不是平台保证。这里不需要删除 OpenAI Platform 中的 Tunnel，也不需要重新初始化本机 tunnel-client Profile。

## 安全边界

- 所有路径都必须位于 `LOCAL_OPS_ROOT` 下；拒绝 `..` 越界和符号链接越界；
- 除非明确设置 `overwrite=true`，否则不会覆盖已有文件；
- `expected_sha256` 可以防止覆盖读取后又被其他程序修改的文件；
- 删除非空目录必须明确设置 `recursive=true`，且工作区根目录永远不能被删除；
- 移动和重命名不会替换已存在的目标；
- 文件默认限制为 2 MiB，可通过 `LOCAL_OPS_MAX_BYTES` 调整；
- 不暴露通用 Shell 或管理员工具；Git 使用固定参数数组启动，不经过 Shell，远程工具默认关闭；
- 协议日志写入 stderr，stdout 只用于 MCP JSON-RPC 消息。

## 通过 Secure MCP Tunnel 连接 Hosted Chat

Hosted Chat 无法直接启动本机 STDIO 进程。OpenAI Secure MCP Tunnel 可以把 ChatGPT 的工具调用转发到本机，同时不需要开放入站防火墙端口。

### Windows 快速开始

1. 准备 Node.js 20、一个明确授权的本地项目目录，以及官方 `tunnel-client`。
2. 在 OpenAI Platform 创建 Tunnel，为它选择目标 `ChatGPT workspace`，并创建具备 Tunnels Read + Use 权限的 Runtime API Key。
3. 双击仓库根目录的 `Local-Ops.bat`，选择 `1. First-time setup` 完成首次配置。
4. 再选择 `2. Start Tunnel` 并保持窗口开启。
5. 在 ChatGPT 开发者模式中创建 Tunnel 连接的应用，从“可用隧道”列表选择对应 Tunnel，然后先执行一次只读目录测试。

`tunnel-client` 是 OpenAI Secure MCP Tunnel 的官方传输客户端；本仓库的 `server.mjs` 才是提供受限文件工具的 MCP 服务端。二者配套使用，不能互相替代。仓库不再分发或跟踪官方客户端二进制文件。

后续细节按场景查阅，避免在多份文档中维护同一套操作规则：

- 第一次搭建：[零基础完整教程](./docs/zh-CN/ChatGPT本地文件访问-零基础教程.md)
- 配置字段、日常启动、重新初始化和排错：[Tunnel 综合配置速查](./docs/zh-CN/ChatGPT本地文件访问-Tunnel配置速查.md)
- 迁移到新电脑：[换电脑只看这一页](./docs/zh-CN/换电脑只看这一页.md)

## 配置与密钥

- `config/local-ops.example.psd1`：可提交的脱敏模板；
- `config/local-ops.psd1`：每台电脑单独生成的真实配置，已被 Git 忽略；
- Runtime API Key：不保存在仓库中，脚本需要时临时询问；
- `.mcp.json`：本地插件入口，安装前应确认 `LOCAL_OPS_ROOT` 指向预期工作区。

不要为了方便把工作区设为整个磁盘、用户主目录或系统目录。推荐一个 Local Ops 实例只授权一个明确项目。

## 开源与安全

- 许可证：[MIT License](./LICENSE)
- 安全问题：[SECURITY.md](./SECURITY.md)
- 参与贡献：[CONTRIBUTING.md](./CONTRIBUTING.md)

本项目在设计、编码和文档编写过程中使用了 AI 编程工具辅助。维护者会检查改动并运行自动测试，但自动测试不等于安全审计。
