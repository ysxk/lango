# 自部署

## Docker：局域网 / 单机

需要 Docker Engine + Compose v2（macOS 可用 Docker Desktop 或 OrbStack），机器必须能访问所选模型服务。模型配额、可用地区与付费计划由部署者确认。

在项目根目录：

```sh
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

执行最后一条命令两次，把不同的结果分别填入 `POSTGRES_PASSWORD` 和 `LANGO_JWT_SECRET`。数据库密码使用十六进制，避免 URL 特殊字符需要转义的问题。在本地编辑器里填入新生成的 `LANGO_GOOGLE_API_KEY`，不要把密钥发到聊天或提交 Git。

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d --build
curl http://127.0.0.1:8000/healthz
docker compose --env-file deploy/.env -f deploy/compose.yaml exec server \
  lango create-admin --email you@example.com --display-name 管理员
```

管理员密码由隐藏输入提示读取，要求 10–128 个字符。然后通过 App 登录管理员账号，在设置中生成邀请码，或使用：

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml exec server \
  lango invite --email you@example.com --max-uses 1 --hours 72
```

默认 `127.0.0.1:8000` 不向其他机器开放。要给同一可信 Wi-Fi 下的手机使用，将 `.env` 中 `BIND_ADDRESS=0.0.0.0`，重新 `up -d`，App 服务器填写 `http://电脑局域网IP:8000`。防火墙仅允许可信局域网。**HTTP 不加密密码、令牌、音频；不能在公网或不可信 Wi-Fi 使用。** 日常使用优先 HTTPS。

Android 真机通过 USB 调试也可运行 `adb reverse tcp:8000 tcp:8000`，App 填 `http://127.0.0.1:8000`；Android 模拟器访问宿主机通常使用 `http://10.0.2.2:8000`。

未配置模型密钥时仍可启动、注册和浏览数据；真实对话与记忆提取会明确报错，不会伪造成功结果。

## 公网 HTTPS

先把域名 A/AAAA 指向部署机器，允许公网访问 80/443。不要公开 PostgreSQL 或直接公开 8000。

编辑 `deploy/.env`：

```dotenv
LANGO_ENVIRONMENT=production
BIND_ADDRESS=127.0.0.1
PUBLIC_DOMAIN=lango.example.com
LANGO_ALLOWED_ORIGINS=["https://lango.example.com"]
```

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml --profile public up -d --build
curl https://lango.example.com/healthz
```

App 填 `https://lango.example.com`。Caddy 负责 TLS 与 WebSocket 代理。若另行托管 Web 客户端，把它的完整 HTTPS origin 加入 `LANGO_ALLOWED_ORIGINS`，不能使用通配符。Caddy 默认不打开访问日志，避免记录一次性 WS ticket；如果自加代理日志，必须移除 URL 查询参数。

## 配置

| 变量 | 含义 |
| --- | --- |
| `LANGO_GOOGLE_API_KEY` | 仅服务端保存的 Gemini API Key |
| `LANGO_TEXT_MODEL` | 默认 `gemini-3.8-flash`，音频输入、文本输出 |
| `LANGO_TTS_MODEL` | 默认 `gemini-3.8-flash-lite-tts` |
| `LANGO_LIVE_MODEL` | 默认 `gemini-3.8-live` |
| `LANGO_EMBEDDING_MODEL` | 默认 `gemini-embedding-001` |
| `LANGO_DEFAULT_ENGINE` | `cascade` 或 `live` |
| `LANGO_DAILY_MINUTES` | 每用户每日语音时间配额，默认 60；不是精确的货币预算 |
| `LANGO_ALLOWED_ORIGINS` | JSON 数组，匹配浏览器 origin；原生客户端不依赖 CORS |
| `LANGO_JWT_SECRET` | 至少 32 字符的随机服务端签名密钥 |

模型参数与更多限制见 [服务端说明](../server/README.md)。更换模型 ID 前需要验证输入/输出能力与 SDK 参数，不能仅凭名字推断双向音频。修改 `.env` 后重新执行 `up -d`，仅 `restart` 不会重新注入环境变量。

## 数据与备份

Compose 使用命名卷：Postgres 保存账号、会话、文字记录、记忆索引、向量和任务；memory 卷用于 worker 的本地运行状态；Caddy 卷保存证书。Mem0 冗余原始消息/变更历史仅在内存中处理。**`docker compose down -v` 会删除数据，不用于日常停机。**

一致性备份时先停 server 和 worker，导出数据库并备份 memory 卷；恢复时使用匹配的代码版本和同一批备份。备份包含个人数据，必须加密、限制访问并设置保留期。升级前先备份，数据库迁移随 server 启动执行。

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml logs --tail=100 server worker
docker compose --env-file deploy/.env -f deploy/compose.yaml stop
```

目前一个 memory worker 串行运行，不能为了扩容直接复制 worker。API 实例的实际并发能力、模型配额和部署区延迟需要自行压测。

## 本地开发与排错

详见 [服务端 README](../server/README.md) 和 [App README](../app/README.md)。Flutter Web 调试需要把开发服务器 origin（例如 `http://127.0.0.1:8080`）加入服务端白名单；麦克风仅在安全上下文（HTTPS 或 localhost）可用。

- 登录连接失败：检查手机到服务端网络、端口、防火墙、TLS 证书与 URL，不要关闭证书校验。
- API 启动失败：检查 JWT 随机密钥、数据库连接、迁移、生产环境 HTTPS origin。
- 对话失败：检查模型是否可用、API Key 权限、付费配额与部署地区；客户端不会显示敏感上游错误。
- 记忆暂未出现：结束自由对话后由 worker 异步提取；场景角色扮演不当作真实个人经历入库。查看 worker 状态。
- 外放产生回声：使用半双工或按住说话模式，或戴耳机；不要把软件静音检测当作硬件回声消除验证。
