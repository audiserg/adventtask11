import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import * as mcpConfig from './mcp-config.js';

// Хранилище подключений к серверам
const connections = new Map();

/**
 * Подключается к MCP серверу
 */
export async function connect(serverId, url) {
  try {
    // Если уже подключен, возвращаем существующее подключение
    if (connections.has(serverId)) {
      const existing = connections.get(serverId);
      if (existing.status === 'connected') {
        return { success: true, message: 'Already connected', client: existing.client };
      }
    }

    // Создаем новый клиент
    const client = new Client(
      {
        name: 'mcp-client',
        version: '1.0.0',
      },
      {
        capabilities: {},
      }
    );

    // Подключаемся через HTTP
    // Для HTTP транспорта используем fetch для отправки запросов
    const transport = {
      url: url,
      send: async (request) => {
        try {
          const response = await fetch(`${url}/mcp`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              method: request.method,
              params: request.params,
            }),
          });

          if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
          }

          return await response.json();
        } catch (error) {
          throw new Error(`Failed to send request: ${error.message}`);
        }
      },
    };

    // Сохраняем информацию о подключении
    connections.set(serverId, {
      client,
      transport,
      url,
      status: 'connected',
      connectedAt: new Date(),
    });

    // Тестируем подключение
    try {
      await listTools(serverId);
    } catch (error) {
      connections.set(serverId, {
        ...connections.get(serverId),
        status: 'error',
        error: error.message,
      });
      throw error;
    }

    return { success: true, client };
  } catch (error) {
    connections.set(serverId, {
      status: 'error',
      error: error.message,
      connectedAt: new Date(),
    });
    return { success: false, error: error.message };
  }
}

/**
 * Отключается от MCP сервера
 */
export async function disconnect(serverId) {
  if (connections.has(serverId)) {
    connections.delete(serverId);
    return { success: true };
  }
  return { success: false, error: 'Server not connected' };
}

/**
 * Получает список инструментов с сервера
 */
export async function listTools(serverId) {
  const connection = connections.get(serverId);
  if (!connection || connection.status !== 'connected') {
    throw new Error(`Server ${serverId} is not connected`);
  }

  try {
    const response = await connection.transport.send({
      method: 'tools/list',
      params: {},
    });

    return {
      success: true,
      tools: response.tools || [],
    };
  } catch (error) {
    throw new Error(`Failed to list tools: ${error.message}`);
  }
}

/**
 * Получает список инструментов со всех подключенных серверов
 */
export async function listAllTools() {
  const allTools = [];
  
  for (const [serverId, connection] of connections.entries()) {
    if (connection.status === 'connected') {
      try {
        const result = await listTools(serverId);
        const server = mcpConfig.getServer(serverId);
        
        result.tools.forEach(tool => {
          allTools.push({
            ...tool,
            serverId,
            serverName: server?.name || serverId,
          });
        });
      } catch (error) {
        console.error(`Error listing tools from ${serverId}:`, error);
      }
    }
  }
  
  return {
    success: true,
    tools: allTools,
  };
}

/**
 * Вызывает инструмент на сервере
 */
export async function callTool(serverId, toolName, args = {}) {
  const connection = connections.get(serverId);
  if (!connection || connection.status !== 'connected') {
    throw new Error(`Server ${serverId} is not connected`);
  }

  try {
    const response = await connection.transport.send({
      method: 'tools/call',
      params: {
        name: toolName,
        arguments: args,
      },
    });

    return {
      success: true,
      result: response,
    };
  } catch (error) {
    throw new Error(`Failed to call tool: ${error.message}`);
  }
}

/**
 * Получает статус подключения к серверу
 */
export function getServerStatus(serverId) {
  const connection = connections.get(serverId);
  if (!connection) {
    return { status: 'disconnected' };
  }

  return {
    status: connection.status,
    url: connection.url,
    connectedAt: connection.connectedAt,
    error: connection.error,
  };
}

/**
 * Получает статус всех подключений
 */
export function getAllServersStatus() {
  const statuses = {};
  
  for (const [serverId, connection] of connections.entries()) {
    statuses[serverId] = {
      status: connection.status,
      url: connection.url,
      connectedAt: connection.connectedAt,
      error: connection.error,
    };
  }
  
  return statuses;
}

/**
 * Инициализирует подключения к включенным серверам из конфигурации
 */
export async function initializeConnections() {
  const enabledServers = mcpConfig.getEnabledServers();
  const results = [];

  for (const server of enabledServers) {
    try {
      const result = await connect(server.id, server.url);
      results.push({
        serverId: server.id,
        serverName: server.name,
        ...result,
      });
    } catch (error) {
      results.push({
        serverId: server.id,
        serverName: server.name,
        success: false,
        error: error.message,
      });
    }
  }

  return results;
}

/**
 * Тестирует подключение к серверу без сохранения
 */
export async function testConnection(url) {
  try {
    // Создаем временное подключение
    const testClient = {
      url: url,
      send: async (request) => {
        const response = await fetch(`${url}/mcp`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            method: request.method,
            params: request.params,
          }),
        });

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        return await response.json();
      },
    };

    // Пробуем получить список инструментов
    const response = await testClient.send({
      method: 'tools/list',
      params: {},
    });

    return {
      success: true,
      toolsCount: response.tools?.length || 0,
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
}
