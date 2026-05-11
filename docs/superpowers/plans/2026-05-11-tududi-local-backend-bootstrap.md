# Tududi 本地后端启动修复 Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 tududi 后端能在 Windows PowerShell 环境下成功监听 `localhost:3002`，并让前端 `http://localhost:8080` 通过代理拿到 `/api/*` 响应、可登录管理员账号。

**Architecture:** 用 `backend/.env` 提供后端必需的 3 个环境变量（`NODE_ENV`、`TUDUDI_SESSION_SECRET`、`DB_FILE`），让 `DB_FILE` 指向已有的 `backend/database.sqlite`（避免丢数据）。然后用 `npm run backend:dev`（nodemon，不依赖 bash）启动；用 `npm run user:create` 建一个 admin 账号；最后通过 curl 与浏览器双重验证连通性。

**Tech Stack:** Node.js 22+，Express 4，Sequelize 6 + SQLite，nodemon，PowerShell 5.1（Windows 原生）

**Root cause（已诊断）:**

| 现象 | 原因 |
| --- | --- |
| 前端 8080 报 `ECONNREFUSED → localhost:3002` | 后端没启动 |
| 后端启动后立刻退出 | `NODE_ENV` 未设，触发 [backend/config/config.js:3-12](../../../backend/config/config.js#L3-L12) `process.exit(1)` |
| 即使设了 `NODE_ENV`，登录后 session 也立即失效 | 缺 `TUDUDI_SESSION_SECRET` → config.js 每次启动生成随机值 |
| 重启后空数据库 | 默认 DB 路径是 `backend/db/development.sqlite3`，但已有数据在 `backend/database.sqlite` |

---

## File Structure

| 路径 | 改动 | 作用 |
| --- | --- | --- |
| `backend/.env` | **Create** | 包含 NODE\_ENV / PORT / DB\_FILE / TUDUDI\_SESSION\_SECRET 等本地必需变量 |
| `backend/database.sqlite.bak.<timestamp>` | **Create**（一次性备份） | 操作前的安全副本，事毕可删 |

不修改任何源代码或仓库内已 tracked 文件。`.env` 已被 `.gitignore` 忽略。

---

## Task 1：安全备份现有数据库

**Files:**

Create: `backend/database.sqlite.bak.<timestamp>`

 **Step 1：在仓库根用 PowerShell 备份当前 SQLite 文件**

```
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item backend\database.sqlite "backend\database.sqlite.bak.$ts"
"Backup created: backend\database.sqlite.bak.$ts"
```

预期输出：

```
Backup created: backend\database.sqlite.bak.20260511-HHMMSS
```

*   **Step 2：验证备份存在且大小一致**

```
(Get-Item backend\database.sqlite).Length
(Get-Item "backend\database.sqlite.bak.$ts").Length
```

预期两行数值相同（同字节数）。

---

## Task 2：生成随机 session secret

\*\*Files:\*\*（无文件改动，仅产生一个字符串供 Task 3 使用）

*   **Step 1：用 Node 生成 64 字节十六进制 secret 并保存到 PowerShell 变量**

```
$secret = node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
"Generated secret length: $($secret.Length)"
```

预期输出：

```
Generated secret length: 128
```

> 不要 echo `$secret` 本身到日志/截图——它是会话签名密钥。

---

## Task 3：创建 `backend/.env`

**Files:**

Create: `backend/.env`

 **Step 1：写出** `**.env**` **文件，注入 Task 2 生成的 secret**

```
@"
NODE_ENV=development
HOST=0.0.0.0
PORT=3002

# 指回仓库已有的 sqlite 文件（相对 backend/ 目录）
DB_FILE=database.sqlite

FRONTEND_URL=http://localhost:8080
BACKEND_URL=http://localhost:3002

TUDUDI_SESSION_SECRET=$secret

# 本地开发：禁用所有非必需后台服务，减少噪音
DISABLE_SCHEDULER=true
DISABLE_TELEGRAM=true
ENABLE_EMAIL=false

# 关闭可选 feature flags
FF_ENABLE_BACKUPS=false
FF_ENABLE_CALDAV=false
FF_ENABLE_CALENDAR=false
FF_ENABLE_HABITS=false
FF_ENABLE_MCP=false

# 本地无反向代理
TUDUDI_TRUST_PROXY=false

# 关掉密码以外的认证方式，简化首次登录
OIDC_ENABLED=false
PASSWORD_AUTH_ENABLED=true
"@ | Set-Content -Encoding utf8 backend\.env
"Wrote backend\.env"
```

> 注意：`Set-Content -Encoding utf8` 写出的是 UTF-8 with BOM。dotenv 能识别 BOM；但若后续某行解析异常，改用 `-Encoding ascii` 重写一次。

*   **Step 2：验证** `**.env**` **内容（不打印 secret）**

```
Get-Content backend\.env | Where-Object { $_ -notmatch 'SESSION_SECRET' }
```

预期看到 `NODE_ENV=development`、`PORT=3002`、`DB_FILE=database.sqlite` 等行；`TUDUDI_SESSION_SECRET=` 那一行被过滤掉。

*   **Step 3：确认** `**.env**` **已被 gitignore（不会被误提交）**

```
git check-ignore -v backend\.env
```

预期输出形如：

```
.gitignore:NN:.env    backend/.env
```

（命中规则即可，具体行号不重要）

---

## Task 4：数据库健康检查

\*\*Files:\*\*（无改动）

*   **Step 1：跑** `**npm run db:status**` **确认 .env 被读到、DB 能连**

```
npm run db:status
```

预期输出包含：

```
📂 Database Configuration:
   Storage: <绝对路径>\backend\database.sqlite
   ...
   Environment: development
✅ Database connection successful

📊 Table Statistics:
   Users: <N> records
   ...
```

**判断分支：**

*   若 `Users: 0 records` → 继续 Task 5（建账号）
*   若 `Users: 1+ records` 且**记得密码** → 跳过 Task 5，直接 Task 6
*   若 `Users: 1+ records` 且**忘记密码** → 跳到 Task 5（`user:create` 对同邮箱会更新密码而不是报错，见 [backend/scripts/user-create.js:69-73](../../../backend/scripts/user-create.js#L69-L73)）
*   若整个命令报错（找不到表、缺字段等） → 跳到附录 A 重建 schema

---

## Task 5：创建/更新管理员账号

\*\*Files:\*\*（无改动）

*   **Step 1：执行** `**user:create**` **建 admin**

```
npm run user:create -- admin@local.test admin12345 true
```

> 三个参数：`<email> <password> [is_admin]`。npm 的 `--` 是把后续参数透传给底层 `node scripts/user-create.js`。

预期输出（新建场景）：

```
Creating user with email: admin@local.test
User created successfully
Email: admin@local.test
User ID: <number>
Created: <ISO timestamp>
Admin: yes
```

或（已存在场景）：

```
User exists, password updated
Email: admin@local.test
User ID: <number>
Admin: yes
```

*   **Step 2：复查账号已落库**

```
npm run db:status
```

预期 `Users: 1 records`（或在原数基础上 +1）。

---

## Task 6：启动后端并确认 3002 监听

\*\*Files:\*\*（无改动）

*   **Step 1：另开一个 PowerShell 窗口（保持本窗口跑后续验证），启动后端**

在**第 1 个 PowerShell 窗口**运行：

```
npm run backend:dev
```

预期日志依次出现：

```
[nodemon] starting `node app.js`
Using database file '<...>\backend\database.sqlite'
[Config] TUDUDI_TRUST_PROXY=false parsed as boolean false
...
Server running on http://0.0.0.0:3002
```

> 若看到 `NODE_ENV should be one of...` 立即退出 → 说明 `.env` 没被加载（dotenv 默认从 cwd 读 `.env`，而 nodemon 的 cwd 是 `backend/`，所以路径 `backend/.env` 是对的；若仍失败，先 `Get-Location` 确认在仓库根，然后重试）。

*   **Step 2：在**第 2 个 PowerShell 窗口**验证端口监听**

```
netstat -ano | Select-String ':3002\s+.*LISTENING'
```

预期至少一行包含 `0.0.0.0:3002` 或 `[::]:3002` + `LISTENING` + 一个 PID。

*   **Step 3：本机直连后端 health/registration endpoint**

```
curl.exe -s -o NUL -w "HTTP %{http_code}`n" http://localhost:3002/api/registration-status
```

预期：

```
HTTP 200
```

> 用 `curl.exe`（而不是 PowerShell 内建的 `curl` 别名 = `Invoke-WebRequest`），避免参数差异。

---

## Task 7：验证前端代理 + 登录链路

\*\*Files:\*\*（无改动）

*   **Step 1：通过前端 8080 反代访问后端，确认** `**ECONNREFUSED**` **已消失**

```
curl.exe -s -o NUL -w "HTTP %{http_code}`n" http://localhost:8080/api/registration-status
```

预期：

```
HTTP 200
```

若仍出现 `Bad Gateway` 或 `502`，说明前端 webpack-dev-server 缓存了失败的 upstream；回到第 1 个窗口 Ctrl+C 重启 `npm run frontend:dev`。

*   **Step 2：浏览器登录验证**

打开 `http://localhost:8080`，应看到登录页。用 Task 5 的凭证登录：

*   Email：`admin@local.test`
*   Password：`admin12345`

预期：登录成功、跳到 Today 视图、左侧栏可见。

*   **Step 3：在第 1 个窗口（后端日志）确认登录请求被处理**

后端日志应出现一行 200 的 `POST /api/login` 或类似 access log。无 5xx 错误。

---

## Task 8：清理 + 收尾

\*\*Files:\*\*（可选删除备份）

*   **Step 1：确认一切正常后删除 Task 1 的备份**

```
Remove-Item backend\database.sqlite.bak.*
"Backups removed"
```

> 若你打算重做 Task 4–7 调试，先**别**删，保留作为回滚点。

*   **Step 2：把本次得到的可复用经验加入到** [**CLAUDE.md**](../../../CLAUDE.md)**（可选）**

Plan 不强制此步——但建议在 CLAUDE.md "Common Commands / Gotchas" 章节追加：

*   `.env` 必需键最小集：`NODE_ENV`、`TUDUDI_SESSION_SECRET`、`DB_FILE`
*   Windows 不能用 `npm start`（bash 脚本），需要分别 `backend:dev` + `frontend:dev`
*   默认 DB 路径与历史路径冲突的处理

（之前的 /init 会话里我已提议过这块改动；此处只是关联引用。）

---

## 附录 A：如果 Task 4 schema 报错（Sequelize "no such table" 等）

说明 `backend/database.sqlite` 不是当前代码期望的 schema 版本（很可能是旧 init 留下的）。两种处理：

**A1. 重建 schema（保留备份做对比）：**

```
npm run db:migrate
```

若 migrate 仍报错（base schema 不在），降级使用：

```
npm run db:init    # 警告：清空所有数据
```

重做完 Task 4 → Task 7。

**A2. 切换到种子数据库（彻底重来 + 演示数据）：**

```
# .env 里把 DB_FILE 改回默认（注释掉 DB_FILE 行）
npm run db:reset-and-seed
```

之后用种子账号 `test@tududi.com` / `password123` 登录，跳过 Task 5。

---

## 附录 B：常见排障

| 症状 | 检查项 |
| --- | --- |
| 后端日志 `NODE_ENV should be one of...` | `.env` 没被 dotenv 读到——确认是 `backend/.env` 不是仓库根 `.env` |
| 后端日志 `SequelizeConnectionError: SQLITE_CANTOPEN` | `DB_FILE` 相对路径错误，改用绝对路径或留默认值并配合 `db:init` |
| 登录 200 但前端立刻被踢回登录页 | session cookie 没保存——浏览器跨源 cookie 问题，确认从 `localhost:8080` 而不是 `127.0.0.1:8080` 访问 |
| 登录 429 Too Many Requests | 触发 auth rate limit（5 次/15 分钟），等 15 分钟或在 `.env` 加 `RATE_LIMITING_ENABLED=false` |
| 浏览器 Console 一堆 CORS 错误 | `TUDUDI_ALLOWED_ORIGINS` 缺 `http://localhost:8080`——默认值已含此项，除非你显式覆盖了它 |

---

## Self-Review 检查表

*   ✅ 每一步含可执行命令 + 期望输出
*   ✅ Windows PowerShell 语法（`$var`、`@""@` heredoc、`-Encoding utf8`、`curl.exe`）
*   ✅ 不依赖 bash 脚本（`scripts/start-all-dev.sh`、`backend/cmd/start.sh` 已绕开）
*   ✅ secret 全程不落盘到日志 / shell history（生成后只存内存变量，写入 .env 文件后不再回显）
*   ✅ 有数据库备份与回滚路径（附录 A）
*   ✅ 处理"已有 user / 没有 user / schema 损坏"三种分支
*   ✅ 验证步骤覆盖：端口监听 → 后端直连 → 前端代理 → 浏览器登录 → 后端日志

**Spec coverage 验证：**

| 原始问题 | 对应 Task |
| --- | --- |
| 8080 代理 `/api/*` 报 ECONNREFUSED | Task 6 + Task 7 |
| 默认账号是什么 | Task 5（创建确定账号）+ 附录 A2（用 seed 账号） |
| Windows 本地启动方式不清晰 | Task 6 双窗口模式 |
| `.env` 缺失导致后端不起 | Task 3 |
| 已有 sqlite 文件路径错位 | Task 3 的 `DB_FILE=database.sqlite` + 附录 A |