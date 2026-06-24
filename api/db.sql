-- 色块连击 · 通路得分 — 数据库初始化
CREATE DATABASE IF NOT EXISTS game_db DEFAULT CHARACTER SET utf8mb4;
USE game_db;

-- 成绩表
CREATE TABLE IF NOT EXISTS scores (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    player_name VARCHAR(50),
    score INT NOT NULL DEFAULT 0,
    best_streak INT DEFAULT 0,
    path_count INT DEFAULT 0,
    max_hit INT DEFAULT 0,
    avg_pts INT DEFAULT 0,
    max_dist INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_device (device_id),
    INDEX idx_score (score)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 用户表（注册账号）
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nickname VARCHAR(50) UNIQUE NOT NULL,
    player_id VARCHAR(20) NOT NULL,
    password VARCHAR(255) NOT NULL,
    device_id VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_nickname (nickname),
    INDEX idx_player_id (player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
