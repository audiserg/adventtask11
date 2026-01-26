import express from 'express';

const app = express();
const PORT = process.env.MCP_SERVER_PORT || 3001;

app.use(express.json());

// Моковые данные для Bluetooth устройств
const mockDevices = [
  { id: 'device-1', name: 'Bluetooth Headphones', address: '00:11:22:33:44:55', connected: false },
  { id: 'device-2', name: 'Wireless Mouse', address: 'AA:BB:CC:DD:EE:FF', connected: true },
  { id: 'device-3', name: 'Smart Watch', address: '11:22:33:44:55:66', connected: false },
];

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
              description: 'MAC адрес устройства (альтернатива deviceId)',
            },
          },
          required: ['deviceId'],
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
          },
          required: ['deviceId'],
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
            data: {
              type: 'string',
              description: 'Данные для отправки (строка или hex)',
            },
          },
          required: ['deviceId', 'data'],
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
        // Имитация сканирования
        await new Promise(resolve => setTimeout(resolve, Math.min(duration * 100, 1000)));
        
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                devicesFound: mockDevices.length,
                devices: mockDevices.map(d => ({
                  id: d.id,
                  name: d.name,
                  address: d.address,
                  rssi: Math.floor(Math.random() * -30) - 50, // Моковый уровень сигнала
                })),
                scanDuration: duration,
              }, null, 2),
            },
          ],
        };
      }

      case 'bluetooth_connect': {
        const deviceId = args?.deviceId || args?.deviceAddress;
        if (!deviceId) {
          throw new Error('deviceId или deviceAddress обязателен');
        }

        const device = mockDevices.find(d => d.id === deviceId || d.address === deviceId);
        if (!device) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: `Устройство с ID ${deviceId} не найдено`,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        if (device.connected) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: `Устройство ${device.name} уже подключено`,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        // Имитация подключения
        await new Promise(resolve => setTimeout(resolve, 500));
        device.connected = true;

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                device: {
                  id: device.id,
                  name: device.name,
                  address: device.address,
                  connected: true,
                },
                message: `Успешно подключено к ${device.name}`,
              }, null, 2),
            },
          ],
        };
      }

      case 'bluetooth_disconnect': {
        const deviceId = args?.deviceId;
        if (!deviceId) {
          throw new Error('deviceId обязателен');
        }

        const device = mockDevices.find(d => d.id === deviceId);
        if (!device) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: `Устройство с ID ${deviceId} не найдено`,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        if (!device.connected) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: `Устройство ${device.name} не подключено`,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        device.connected = false;

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                device: {
                  id: device.id,
                  name: device.name,
                  address: device.address,
                  connected: false,
                },
                message: `Отключено от ${device.name}`,
              }, null, 2),
            },
          ],
        };
      }

      case 'bluetooth_get_devices': {
        const connectedOnly = args?.connectedOnly || false;
        let devices = mockDevices;

        if (connectedOnly) {
          devices = mockDevices.filter(d => d.connected);
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                devices: devices.map(d => ({
                  id: d.id,
                  name: d.name,
                  address: d.address,
                  connected: d.connected,
                })),
                total: devices.length,
                connected: devices.filter(d => d.connected).length,
              }, null, 2),
            },
          ],
        };
      }

      case 'bluetooth_send_data': {
        const deviceId = args?.deviceId;
        const data = args?.data;

        if (!deviceId || !data) {
          throw new Error('deviceId и data обязательны');
        }

        const device = mockDevices.find(d => d.id === deviceId);
        if (!device) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: `Устройство с ID ${deviceId} не найдено`,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        if (!device.connected) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: `Устройство ${device.name} не подключено`,
                }, null, 2),
              },
            ],
            isError: true,
          };
        }

        // Имитация отправки данных
        await new Promise(resolve => setTimeout(resolve, 200));

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                device: {
                  id: device.id,
                  name: device.name,
                },
                dataSent: data,
                bytesSent: Buffer.from(data).length,
                message: `Данные успешно отправлены на ${device.name}`,
              }, null, 2),
            },
          ],
        };
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

// Запуск сервера
app.listen(PORT, () => {
  console.log(`Bluetooth MCP Server запущен на порту ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`MCP endpoint: http://localhost:${PORT}/mcp`);
});
