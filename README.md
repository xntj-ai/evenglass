# evenglass

Even Realities G2 智能眼镜 ↔ PC 的实时数据中继。

## 架构

```
[G2 眼镜]
   ↓ BLE
[MatePad Mini + 自写 Kotlin App]
   ↓ HTTPS
[北京实验服 Phoenix]
   ↑ HTTPS / WebSocket / LiveView
[PC 端业务]
```

## 当前进度

- [x] G2 BLE GATT 验证（nRF Connect 在卓易通容器扫到、连上、列出 services）
- [x] 技术栈选定：Phoenix (Elixir) + Kotlin (Android)
- [x] 服务器选定：北京实验服 101.42.154.134
- [ ] Phoenix 工程骨架（计划在服务器 Docker 中 `mix phx.new`）
- [ ] Docker Compose（Phoenix + Postgres）
- [ ] g2.xntj.tv DNS + Caddy HTTPS
- [ ] Android App（Kotlin + BLE）
- [ ] 端到端 demo：PC → 服务器 → 手机 → G2 显示文字

## 文档

| 文件 | 用途 |
|------|------|
| [memory/MEMORY.md](../.claude/projects/C--Users-ZPP-evenglass/memory/MEMORY.md) | 项目记忆索引 |
| memory/architecture.md | 系统架构详解 |
| memory/g2-protocol-knowledge.md | G2 BLE 协议已知信息 |
| memory/tech-stack-decision.md | 技术栈选择理由 |

## 域名

`g2.xntj.tv`（待配，Cloudflare/DNSPod）

## 服务器

北京实验服「拼拼实验室」(101.42.154.134) — 全新 Ubuntu 22.04 LTS，OpenClaw 已清空。
