# Lango

**把英语说进生活里。** 一个可自部署的 AI 英语口语练习应用：FastAPI 服务端，跨会话长期记忆；客户端处于未开发状态（规划 Flutter / 多端自建）。

Lango 目前是开发代号。首版覆盖自由对话、场景角色扮演、学习档案、历史记录与记忆管理；专注真实练习，不用虚高分数代替反馈。

## 组成

- **客户端（未开发 / 待实现）**：目前代码库仅包含服务端与部署配置，客户端处于未开发状态；接入规范参见 [接口与语音协议](docs/protocol.md)。
- **服务端双引擎**：默认 Gemini 音频输入 → 流式文字 → TTS；可切换 Gemini Live 按轮音频。模型与密钥全部配置在服务端。
- **长期记忆**：Mem0 OSS + 异步 worker，Postgres 保存业务状态；记忆可查看、删除、全部遗忘或关闭。角色扮演不会冒充真实个人经历。
- **自部署**：邀请码多用户，Postgres + pgvector，局域网或 Caddy HTTPS 公网入口。

```
客户端（待开发 / 自建接入）
  ├─ HTTPS REST：账户、档案、场景、历史、记忆
  └─ WebSocket：录音、文字、字幕、音频、取消与播放确认
       FastAPI ── Gemini Cascade / Live
          │
       Postgres + pgvector ── Memory worker / Mem0
```

## 运行

1. 按 [自部署指南](docs/self-hosting.md) 配置 `deploy/.env`、启动容器、创建管理员与邀请码。
2. 服务端提供标准的 REST 与 WebSocket 协议，可按照 [接口与语音协议](docs/protocol.md) 接入或自建客户端。

本地不用 Docker 也可以运行，见 [服务端说明](server/README.md)。没有配置有效模型密钥时可以测试账户和界面流程，但**不能进行真实 AI 对话或记忆提取**。项目不内置模型密钥，不提供伪造的在线结果。

## 开发检查

```sh
cd server
uv sync --frozen
uv run ruff check .
uv run pytest
```

CI 运行服务端代码检查、测试和容器构建。客户端代码目前标记为未开发。真实模型测试可能产生费用。

## 文档

- [部署与配置](docs/self-hosting.md)
- [接口与语音协议](docs/protocol.md)
- [隐私及数据边界](docs/privacy.md)
- [验证记录](docs/verification.md)

## 范围

首版不是发音评分器。轮后纠错卡片、生词本/间隔复习、考试测评、管理后台和完整账号注销流程不在当前版本中。供应商模型能力、价格与地区规则以其当前文档及实际 API 响应为准。

## License

Apache-2.0，见 [LICENSE](LICENSE)。第三方库遵循各自许可证。
