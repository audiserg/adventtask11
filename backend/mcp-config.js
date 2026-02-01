import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CONFIG_FILE = path.join(__dirname, 'mcp-servers.json');

// Структура конфигурации
const DEFAULT_CONFIG = {
  servers: [],
};

/**
 * Загружает конфигурацию из файла
 */
export function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = fs.readFileSync(CONFIG_FILE, 'utf8');
      const config = JSON.parse(data);
      
      // Валидация структуры
      if (!config.servers || !Array.isArray(config.servers)) {
        console.warn('⚠️ Invalid config structure, using default');
        return DEFAULT_CONFIG;
      }
      
      return config;
    } else {
      // Создаем файл с дефолтной конфигурацией
      saveConfig(DEFAULT_CONFIG);
      return DEFAULT_CONFIG;
    }
  } catch (error) {
    console.error('❌ Error loading MCP config:', error);
    return DEFAULT_CONFIG;
  }
}

/**
 * Сохраняет конфигурацию в файл
 */
export function saveConfig(config) {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
    return { success: true };
  } catch (error) {
    console.error('❌ Error saving MCP config:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Получает все серверы
 */
export function getAllServers() {
  const config = loadConfig();
  return config.servers || [];
}

/**
 * Получает сервер по ID
 */
export function getServer(serverId) {
  const servers = getAllServers();
  return servers.find(s => s.id === serverId);
}

/**
 * Добавляет новый сервер
 */
export function addServer(serverConfig) {
  const config = loadConfig();
  
  if (!serverConfig.id || !serverConfig.name) {
    return { success: false, error: 'id и name обязательны' };
  }
  if (config.servers.find(s => s.id === serverConfig.id)) {
    return { success: false, error: `Сервер с ID ${serverConfig.id} уже существует` };
  }

  const hasUrl = serverConfig.url != null && String(serverConfig.url).trim() !== '';
  const hasCommand = serverConfig.command != null && String(serverConfig.command).trim() !== '';
  if (!hasUrl && !hasCommand) {
    return { success: false, error: 'Укажите url или command' };
  }
  if (hasUrl && hasCommand) {
    return { success: false, error: 'Укажите либо url, либо command+args' };
  }
  if (hasUrl) {
    try {
      new URL(serverConfig.url);
    } catch (error) {
      return { success: false, error: 'Некорректный URL' };
    }
  }

  const newServer = {
    id: serverConfig.id,
    name: serverConfig.name,
    enabled: serverConfig.enabled !== undefined ? serverConfig.enabled : true,
    description: serverConfig.description || '',
  };
  if (hasUrl) {
    newServer.url = serverConfig.url.trim();
  } else {
    newServer.command = serverConfig.command.trim();
    newServer.args = Array.isArray(serverConfig.args) ? serverConfig.args : [];
    newServer.env = serverConfig.env && typeof serverConfig.env === 'object' ? serverConfig.env : {};
  }

  config.servers.push(newServer);
  const result = saveConfig(config);
  
  if (result.success) {
    return { success: true, server: newServer };
  } else {
    return result;
  }
}

/**
 * Обновляет существующий сервер
 */
export function updateServer(serverId, updates) {
  const config = loadConfig();
  const serverIndex = config.servers.findIndex(s => s.id === serverId);
  
  if (serverIndex === -1) {
    return { success: false, error: `Сервер с ID ${serverId} не найден` };
  }
  
  // Валидация URL если он обновляется
  if (updates.url) {
    try {
      new URL(updates.url);
    } catch (error) {
      return { success: false, error: 'Некорректный URL' };
    }
  }
  
  const allowedFields = ['name', 'url', 'enabled', 'description', 'command', 'args', 'env'];
  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      config.servers[serverIndex][field] = updates[field];
    }
  }
  
  const result = saveConfig(config);
  
  if (result.success) {
    return { success: true, server: config.servers[serverIndex] };
  } else {
    return result;
  }
}

/**
 * Удаляет сервер
 */
export function removeServer(serverId) {
  const config = loadConfig();
  const serverIndex = config.servers.findIndex(s => s.id === serverId);
  
  if (serverIndex === -1) {
    return { success: false, error: `Сервер с ID ${serverId} не найден` };
  }
  
  const removedServer = config.servers[serverIndex];
  config.servers.splice(serverIndex, 1);
  
  const result = saveConfig(config);
  
  if (result.success) {
    return { success: true, server: removedServer };
  } else {
    return result;
  }
}

/**
 * Получает только включенные серверы
 */
export function getEnabledServers() {
  const servers = getAllServers();
  return servers.filter(s => s.enabled);
}
