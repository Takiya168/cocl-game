const express = require('express');
const mysql = require('mysql2');
const redis = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// ---------- MySQL ----------
const db = mysql.createConnection({
    host: 'localhost', user: 'root',
    password: 'Mlyh051002L!', database: 'game_db'
});
db.connect(err => { if (err) throw err; console.log('✅ MySQL 连接成功'); });

// ---------- Redis ----------
const redisClient = redis.createClient();
redisClient.on('connect', () => { console.log('✅ Redis 连接成功'); });
redisClient.on('error', err => { console.error('Redis 错误:', err); });
redisClient.connect();

// ---------- 工具函数 ----------
function generatePlayerId(nickname, password) {
    const ln = nickname.toLowerCase();
    const lp = password.toLowerCase();
    const patterns = ['dream', 'chocolate', '070208', 'ljx'];
    for (const p of patterns) {
        if (ln.includes(p) || lp.includes(p)) return '520-1314';
    }
    const special = {
        'takiya': '520-070208', 'wie0': '051228', 'designant': '050905',
        'pluvio': '060920', 'martian148': '041019', 'xiaomo247': '030123',
        'angelina': 'zfy20051216',
        '寒殇冷离': '060612'
    };
    if (special[ln] !== undefined) return special[ln];
    return String(1000000 + Math.floor(Math.random() * 9000000));
}

// ---------- 注册 ----------
app.post('/api/register', async (req, res) => {
    const { nickname, password, deviceId } = req.body;
    if (!nickname || !password) return res.status(400).json({ error: '缺少参数' });
    if (nickname.length < 1 || nickname.length > 20) return res.status(400).json({ error: '昵称长度1-20个字符' });
    if (password.length < 4) return res.status(400).json({ error: '密码至少4个字符' });
    try {
        const [existing] = await db.promise().query('SELECT id FROM users WHERE nickname = ?', [nickname]);
        if (existing.length > 0) return res.status(400).json({ error: '昵称已被使用' });
        
        let playerId = generatePlayerId(nickname, password);
        
        await db.promise().query(
            'INSERT INTO users (nickname, player_id, password, device_id) VALUES (?, ?, ?, ?)',
            [nickname, playerId, password, deviceId || null]
        );
        
        // 合并匿名成绩
        if (deviceId && deviceId !== playerId) {
            await db.promise().query('UPDATE scores SET device_id = ? WHERE device_id = ?', [playerId, deviceId]);
            const [best] = await db.promise().query('SELECT MAX(score) as ms FROM scores WHERE device_id = ?', [playerId]);
            if (best[0].ms) await redisClient.zAdd('rank', { score: best[0].ms, value: playerId });
        }
        
        res.json({ success: true, playerId, nickname });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: '注册失败' });
    }
});

// ---------- 登录（昵称或ID） ----------
app.post('/api/login', async (req, res) => {
    const { account, password, deviceId } = req.body;
    if (!account || !password) return res.status(400).json({ error: '缺少参数' });
    try {
        const [rows] = await db.promise().query(
            'SELECT * FROM users WHERE nickname = ? OR player_id = ?', [account, account]
        );
        if (rows.length === 0) return res.status(400).json({ error: '账号或密码错误' });
        const user = rows[0];
        if (password !== user.password) return res.status(400).json({ error: '账号或密码错误' });
        
        // 合并当前设备的匿名成绩
        if (deviceId && deviceId !== user.player_id) {
            await db.promise().query('UPDATE scores SET device_id = ? WHERE device_id = ?', [user.player_id, deviceId]);
            const [best] = await db.promise().query('SELECT MAX(score) as ms FROM scores WHERE device_id = ?', [user.player_id]);
            if (best[0].ms) await redisClient.zAdd('rank', { score: best[0].ms, value: user.player_id });
        }
        
        res.json({ success: true, playerId: user.player_id, nickname: user.nickname });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: '登录失败' });
    }
});

// ---------- 检查昵称是否可用 ----------
app.post('/api/check-nickname', async (req, res) => {
    const { nickname } = req.body;
    if (!nickname) return res.status(400).json({ error: '缺少参数' });
    try {
        const [rows] = await db.promise().query('SELECT id FROM users WHERE nickname = ?', [nickname]);
        res.json({ available: rows.length === 0 });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: '查询失败' });
    }
});

// ---------- 提交成绩 ----------
app.post('/api/submit', async (req, res) => {
    const { deviceId, playerName, score, bestStreak = 0, pathCount = 0, maxHit = 0, avgPts = 0, maxDist = 0 } = req.body;
    if (!deviceId || score === undefined) return res.status(400).json({ error: '缺少参数' });
    try {
        await db.promise().query(
            `INSERT INTO scores (device_id, player_name, score, best_streak, path_count, max_hit, avg_pts, max_dist)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [deviceId, playerName || deviceId, score, bestStreak, pathCount, maxHit, avgPts, maxDist]
        );
        const currentScore = await redisClient.zScore('rank', deviceId);
        if (currentScore === null || score > Number(currentScore)) {
            await redisClient.zAdd('rank', { score, value: deviceId });
        }
        const rank = await redisClient.zRevRank('rank', deviceId);
        res.json({ success: true, rank: rank !== null ? rank + 1 : 0 });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: '服务器错误' });
    }
});

// ---------- 更新昵称 ----------
app.post('/api/update-name', async (req, res) => {
    const { deviceId, playerName } = req.body;
    if (!deviceId || !playerName) return res.status(400).json({ error: '缺少参数' });
    try {
        await db.promise().query('UPDATE scores SET player_name = ? WHERE device_id = ?', [playerName, deviceId]);
        await redisClient.set('player_name:' + deviceId, playerName);
        res.json({ success: true });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: '服务器错误' });
    }
});

// ---------- 排行榜 ----------
app.get('/api/rank', async (req, res) => {
    try {
        const [rows] = await db.promise().query(`
            SELECT s1.device_id, s1.player_name, s1.score, s1.best_streak,
                   s1.path_count, s1.max_hit, s1.avg_pts, s1.max_dist, s1.created_at
            FROM scores s1
            WHERE EXISTS (SELECT 1 FROM users WHERE player_id = s1.device_id)
            AND NOT EXISTS (
                SELECT 1 FROM scores s2
                WHERE s2.device_id = s1.device_id
                AND (s2.score > s1.score OR (s2.score = s1.score AND s2.created_at > s1.created_at))
            )
            ORDER BY s1.score DESC LIMIT 20
        `);
        const list = rows.map(row => ({
            deviceId: row.device_id, playerName: row.player_name || row.device_id,
            score: row.score, bestStreak: row.best_streak || 0, pathCount: row.path_count || 0,
            maxHit: row.max_hit || 0, avgPts: row.avg_pts || 0, maxDist: row.max_dist || 0, createdAt: row.created_at
        }));
        res.json(list);
    } catch (err) { console.error(err); res.status(500).json({ error: '获取排行榜失败' }); }
});

// ---------- 个人数据 ----------
app.get('/api/personal', async (req, res) => {
    const { deviceId } = req.query;
    if (!deviceId) return res.status(400).json({ error: '缺少 deviceId' });
    try {
        const [rows] = await db.promise().query(`
            SELECT device_id, player_name, score, best_streak, path_count,
                   max_hit, avg_pts, max_dist, created_at
            FROM scores WHERE device_id = ?
            ORDER BY created_at DESC LIMIT 50
        `, [deviceId]);
        const list = rows.map(row => ({
            deviceId: row.device_id, playerName: row.player_name || row.device_id,
            score: row.score, bestStreak: row.best_streak || 0, pathCount: row.path_count || 0,
            maxHit: row.max_hit || 0, avgPts: row.avg_pts || 0, maxDist: row.max_dist || 0, createdAt: row.created_at
        }));
        res.json(list);
    } catch (err) { console.error(err); res.status(500).json({ error: '获取个人数据失败' }); }
});

// ---------- 启动 ----------
const PORT = 3000;
app.listen(PORT, () => { console.log(`🚀 API 服务已启动，端口: ${PORT}`); });
