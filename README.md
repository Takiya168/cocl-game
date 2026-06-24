# 色块连击 · 通路得分

一个基于浏览器的色块点击连击小游戏。点击色块得分，同色相邻触发连击，同色通路加成。

## 技术栈

| 模块 | 技术 |
|------|------|
| 前端 | HTML5 + CSS3 + 原生 JavaScript |
| 后端 | Node.js + Express |
| 数据库 | MySQL 8+ |
| 缓存 | Redis |
| 反向代理 | Nginx |
| 部署 | PM2 |

## 目录结构

```
cocl-game/
├── index.html          # 首页
├── game.html           # 游戏页
├── leaderboard.html    # 排行榜
├── profile.html        # 个人主页 / 账号绑定
├── api/
│   ├── server.js       # Node.js API 服务
│   ├── package.json    # 依赖配置
│   ├── db.sql          # 数据库初始化
│   ├── nginx-game.conf # Nginx HTTPS 站点配置（示例）
│   └── nginx-default.conf # Nginx 默认站点 + API 代理
└── README.md
```

## 安装 & 运行

### 前置条件

- Node.js >= 18
- MySQL >= 8.0
- Redis
- Nginx（可选，用于生产环境）

### 1. 数据库

```bash
mysql -u root -p < api/db.sql
```

### 2. 后端 API

```bash
cd api

# 安装依赖
npm install

# 修改 server.js 中的数据库密码
# 第 ~15 行: password: '你的MySQL密码'

# 启动
node server.js
# 或使用 PM2: pm2 start server.js --name game-api
```

API 默认监听 `http://127.0.0.1:3000`

### 3. 前端

直接用浏览器打开 `index.html` 即可游玩（API 需同域部署）。

### 4. Nginx 反向代理（生产环境）

```nginx
# 将 api/nginx-default.conf 放到 /etc/nginx/sites-available/default
# 修改 root 路径为你的前端文件目录
# systemctl reload nginx
```

## API 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/register` | 注册账号 `{nickname, password, deviceId?}` |
| POST | `/api/login` | 登录 `{account, password, deviceId?}` |
| POST | `/api/check-nickname` | 检查昵称是否可用 `{nickname}` |
| POST | `/api/submit` | 提交成绩 `{deviceId, score, ...}` |
| POST | `/api/update-name` | 更新排行榜昵称 `{deviceId, playerName}` |
| GET  | `/api/rank` | 排行榜（每人最好成绩，前20） |
| GET  | `/api/personal?deviceId=xxx` | 个人战绩 |

## 彩蛋 ID

注册时昵称或密码匹配特定条件，可获得固定 ID：

| 条件 | ID |
|------|----|
| 昵称/密码含 `dream`、`chocolate`、`070208`、`ljx` | 520-1314 |
| 昵称 `Takiya` | 520-070208 |
| `wie0` | 051228 |
| `Designant` | 050905 |
| `pluvio` | 060920 |
| `Martian148` | 041019 |
| `XiaoMo247` | 030123 |
| `寒殇冷离` | 060612 |
| `Angelina` | zfy20051216 |

## License

MIT
