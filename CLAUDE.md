# evenglass

Even Realities G2 → 手机 (Kotlin Android) → 服务器 (Phoenix/Elixir) → PC 的实时数据中继。

## 项目目标

让 G2 眼镜的输入（语音/触摸/事件）和输出（文字/图像显示）能完全由 PC 端业务逻辑控制，手机和服务器只做透传层。

## 必读 memory

开始任何任务前 MUST 读：

1. `memory/MEMORY.md` — 项目记忆索引
2. `memory/architecture.md` — 系统架构与数据流
3. `memory/g2-protocol-knowledge.md` — G2 BLE 协议已知信息（NUS service + 待破解音频协议）
4. `memory/tech-stack-decision.md` — Phoenix + Kotlin 选型理由（修改技术栈前先读）

## 跨项目引用（关键）

- 北京服务器详情 → `~/.claude/projects/C--Users-ZPP/memory/openclaw-beijing.md`
- 服务器全局（域名、DNS、TLS）→ `~/.claude/projects/C--Users-ZPP/memory/server.md`
- 凭据查找 → `~/.claude/projects/C--Users-ZPP/memory/credentials-lookup.md`

## 关键参考资源

- G1 EvenDemoApp（Flutter，BLE 协议参考）→ https://github.com/even-realities/EvenDemoApp
- G2 协议逆向（Python）→ https://github.com/i-soxi/even-g2-protocol
- nRF Connect Android（BLE 调试工具）→ https://github.com/nordicsemi/Android-nRF-Connect

## 当前阶段

**工程立项 → 服务器部署**

下一步：
1. SSH 上北京实验服装 Docker
2. 在服务器 Docker 里 `mix phx.new evenglass --app evenglass --module Evenglass --no-html=false`
3. 拉回本地编辑 → push → 部署
4. 配 g2.xntj.tv DNS + Caddy HTTPS
5. 跑通 LiveView Hello World

## 安全约束

- 北京服务器 SSH 密钥：`C:\Users\ZPP\.ssh\beijing.pem`
- 服务器 `.env` 文件：上海 `/home/ubuntu/.env.shared` 模式（统一管理），evenglass 在北京独立 `.env`
- 密钥轮换：同步 `settings.local.json` + 服务器 `.env`

## 工作流

按用户偏好"一步一步来"：
- 每个里程碑跑通后停下来确认再继续
- 不一次性堆所有方案
- 服务器操作前先验证目标，再执行
