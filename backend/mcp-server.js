import express from 'express';
import readline from 'readline';
import * as bleAdapter from './ble-adapter.js';

const app = express();
const PORT = process.env.MCP_SERVER_PORT || 5001;

app.use(express.json());

// Инициализация BLE адаптера при старте
let bleInitialized = false;
bleAdapter.initialize().then(result => {
  if (result.success) {
    bleInitialized = true;
    console.log(`✅ BLE adapter initialized for ${result.platform}`);
  } else {
    console.warn(`⚠️ BLE adapter initialization failed: ${result.error}`);
    console.warn('⚠️ Falling back to mock mode');
  }
});

// Функция для получения списка инструментов
async function listTools() {
  return {
    tools: [
      {
        name: 'bluetooth_scan',
        description: 'Сканирует доступные Bluetooth устройства поблизости',
        inputSchema: {
          type: 'object',
          properties: {
            duration: {
              type: 'number',
              description: 'Длительность сканирования в секундах (по умолчанию 5)',
              default: 5,
            },
          },
        },
      },
      {
        name: 'bluetooth_connect',
        description: 'Подключается к указанному Bluetooth устройству',
        inputSchema: {
          type: 'object',
          properties: {
            deviceId: {
              type: 'string',
              description: 'ID устройства для подключения',
            },
            deviceAddress: {
              type: 'string',
              description: 'MAC адрес устройства (обязателен для подключения)',
            },
          },
          required: ['deviceId', 'deviceAddress'],
        },
      },
      {
        name: 'bluetooth_disconnect',
        description: 'Отключается от указанного Bluetooth устройства',
        inputSchema: {
          type: 'object',
          properties: {
            deviceId: {
              type: 'string',
              description: 'ID устройства для отключения',
            },
            deviceAddress: {
              type: 'string',
              description: 'MAC адрес устройства (обязателен для отключения)',
            },
          },
          required: ['deviceId', 'deviceAddress'],
        },
      },
      {
        name: 'bluetooth_get_devices',
        description: 'Получает список всех известных Bluetooth устройств и их статус подключения',
        inputSchema: {
          type: 'object',
          properties: {
            connectedOnly: {
              type: 'boolean',
              description: 'Показывать только подключенные устройства',
              default: false,
            },
          },
        },
      },
      {
        name: 'bluetooth_send_data',
        description: 'Отправляет данные на подключенное Bluetooth устройство',
        inputSchema: {
          type: 'object',
          properties: {
            deviceId: {
              type: 'string',
              description: 'ID устройства для отправки данных',
            },
            deviceAddress: {
              type: 'string',
              description: 'MAC адрес устройства (обязателен для отправки данных)',
            },
            data: {
              type: 'string',
              description: 'Данные для отправки (строка или hex)',
            },
          },
          required: ['deviceId', 'deviceAddress', 'data'],
        },
      },
    ],
  };
}

// Функция для вызова инструмента
async function callTool(name, args) {

  try {
    switch (name) {
      case 'bluetooth_scan': {
        const duration = args?.duration || 5;
        
        if (!bleInitialized) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: 'BLE adapter not initialized. Please check Bluetooth permissions and system requirements.',
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        try {
          const result = await bleAdapter.scan(duration);
          
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(result, null, 2),
              },
            ],
            isError: !result.success,
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: error.message,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }
      }

      case 'bluetooth_connect': {
        const deviceId = args?.deviceId || args?.deviceAddress;
        const deviceAddress = args?.deviceAddress || deviceId;
        
        if (!deviceId || !deviceAddress) {
          throw new Error('deviceId и deviceAddress обязательны');
        }

        if (!bleInitialized) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: 'BLE adapter not initialized',
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        try {
          const result = await bleAdapter.connect(deviceId, deviceAddress);
          
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(result, null, 2),
              },
            ],
            isError: !result.success,
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: error.message,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }
      }

      case 'bluetooth_disconnect': {
        const deviceId = args?.deviceId;
        const deviceAddress = args?.deviceAddress || deviceId;
        
        if (!deviceId || !deviceAddress) {
          throw new Error('deviceId и deviceAddress обязательны');
        }

        if (!bleInitialized) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: 'BLE adapter not initialized',
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        try {
          const result = await bleAdapter.disconnect(deviceId, deviceAddress);
          
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(result, null, 2),
              },
            ],
            isError: !result.success,
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: error.message,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }
      }

      case 'bluetooth_get_devices': {
        const connectedOnly = args?.connectedOnly || false;

        if (!bleInitialized) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: 'BLE adapter not initialized',
                  devices: [],
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        try {
          const result = await bleAdapter.getDevices(connectedOnly);
          
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(result, null, 2),
              },
            ],
            isError: !result.success,
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: error.message,
                  devices: [],
                }, null, 2),
              },
            ],
            isError: true,
          };
        }
      }

      case 'bluetooth_send_data': {
        const deviceId = args?.deviceId;
        const deviceAddress = args?.deviceAddress || deviceId;
        const data = args?.data;

        if (!deviceId || !deviceAddress || !data) {
          throw new Error('deviceId, deviceAddress и data обязательны');
        }

        if (!bleInitialized) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: 'BLE adapter not initialized',
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        try {
          const result = await bleAdapter.sendData(deviceId, deviceAddress, data);
          
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(result, null, 2),
              },
            ],
            isError: !result.success,
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: error.message,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }
      }

      default:
        throw new Error(`Неизвестный инструмент: ${name}`);
    }
  } catch (error) {
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            success: false,
            error: error.message,
          }, null, 2),
        },
      ],
      isError: true,
    };
  }
}

// HTTP endpoints для MCP протокола
app.post('/mcp', async (req, res) => {
  try {
    const { method, params } = req.body;

    if (method === 'tools/list') {
      const response = await listTools();
      return res.json(response);
    }

    if (method === 'tools/call') {
      const { name, arguments: args } = params || {};
      if (!name) {
        return res.status(400).json({ error: 'Tool name is required' });
      }
      const response = await callTool(name, args || {});
      return res.json(response);
    }

    res.status(400).json({ error: 'Unknown method' });
  } catch (error) {
    console.error('MCP Server error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', server: 'bluetooth-mcp-server' });
});

// --- Stdio MCP transport (для Cursor mcp.json: command + args) ---
const USE_STDIO = process.argv.includes('--stdio');

function writeStdioMessage(obj) {
  console.log(JSON.stringify(obj));
}

async function handleStdioRequest(msg) {
  const { id, method, params } = msg;
  if (id === undefined && !msg.method?.startsWith('notifications/')) return;

  try {
    if (method === 'initialize') {
      return {
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: '2024-11-05',
          serverInfo: { name: 'bluetooth-mcp-server', version: '1.0.0' },
          capabilities: { tools: {} },
        },
      };
    }
    if (method === 'notifications/initialized') return null;

    if (method === 'tools/list') {
      const list = await listTools();
      return { jsonrpc: '2.0', id, result: list };
    }
    if (method === 'tools/call') {
      const { name, arguments: args } = params || {};
      const result = await callTool(name, args || {});
      return { jsonrpc: '2.0', id, result };
    }

    return {
      jsonrpc: '2.0',
      id,
      error: { code: -32601, message: `Method not found: ${method}` },
    };
  } catch (err) {
    return {
      jsonrpc: '2.0',
      id,
      error: { code: -32603, message: err.message || String(err) },
    };
  }
}

function runStdioServer() {
  const rl = readline.createInterface({ input: process.stdin, terminal: false });

  rl.on('line', async (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      writeStdioMessage({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
      return;
    }
    const response = await handleStdioRequest(msg);
    if (response) writeStdioMessage(response);
  });
}

// Запуск: HTTP или stdio
if (USE_STDIO) {
  runStdioServer().catch((err) => {
    console.error('Stdio MCP error:', err);
    process.exit(1);
  });
} else {
  app.listen(PORT, () => {
    console.log(`Bluetooth MCP Server запущен на порту ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log(`MCP endpoint: http://localhost:${PORT}/mcp`);
  });
}
