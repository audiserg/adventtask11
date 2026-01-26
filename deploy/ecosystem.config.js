module.exports = {
  apps: [{
    name: 'deepseek-proxy',
    script: './backend/server.js',
    cwd: '/var/www/ai-chat',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '/var/log/pm2/deepseek-proxy-error.log',
    out_file: '/var/log/pm2/deepseek-proxy-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
