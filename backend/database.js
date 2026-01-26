import sqlite3 from 'sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { promisify } from 'util';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Путь к базе данных
const DB_PATH = join(__dirname, 'chat_memory.db');

let db = null;

// Промис-обертки для sqlite3 методов
function promisifyDb(db) {
  return {
    run: promisify(db.run.bind(db)),
    get: promisify(db.get.bind(db)),
    all: promisify(db.all.bind(db)),
    exec: promisify(db.exec.bind(db)),
    close: promisify(db.close.bind(db)),
  };
}

// Инициализация базы данных
export function initDatabase() {
  return new Promise((resolve, reject) => {
    try {
      // Создаем или открываем базу данных
      db = new sqlite3.Database(DB_PATH, (err) => {
        if (err) {
          console.error('❌ Error opening database:', err);
          reject(err);
          return;
        }
        
        const dbAsync = promisifyDb(db);
        
        // Включаем foreign keys
        db.run('PRAGMA foreign_keys = ON', (err) => {
          if (err) {
            console.error('❌ Error setting foreign keys:', err);
            reject(err);
            return;
          }
          
          // Сначала проверяем, существует ли таблица
          db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='messages'", (tableErr, tableRow) => {
            if (tableErr) {
              console.error('❌ Error checking table existence:', tableErr);
              reject(tableErr);
              return;
            }
            
            const tableExists = !!tableRow;
            
            if (!tableExists) {
              // Таблицы нет - создаем с новыми полями
              db.exec(`
                CREATE TABLE messages (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  role TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'system')),
                  content TEXT NOT NULL,
                  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                  session_id TEXT,
                  is_summarization INTEGER DEFAULT 0,
                  token_count INTEGER
                );
                
                CREATE INDEX idx_timestamp ON messages(timestamp);
                CREATE INDEX idx_content ON messages(content);
                CREATE INDEX idx_is_summarization ON messages(is_summarization);
                CREATE INDEX idx_token_count ON messages(token_count);
              `, (err) => {
                if (err) {
                  console.error('❌ Error creating table:', err);
                  reject(err);
                  return;
                }
                
                console.log('✅ Created messages table with new schema');
                
                // Инициализируем FTS
                initFTS()
                  .then(() => {
                    console.log('✅ Database initialized successfully');
                    resolve(true);
                  })
                  .catch((ftsErr) => {
                    console.error('❌ Error initializing FTS:', ftsErr);
                    console.log('✅ Database initialized (FTS disabled)');
                    resolve(true);
                  });
              });
            } else {
              // Таблица существует - создаем только базовые индексы, если их нет
              db.exec(`
                CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);
                CREATE INDEX IF NOT EXISTS idx_content ON messages(content);
              `, (err) => {
                if (err) {
                  console.warn('⚠️ Error creating basic indexes:', err);
                }
                
                // Выполняем миграцию для существующих таблиц
                migrateDatabase()
                  .then(() => {
                    // Инициализируем FTS после миграции
                    return initFTS();
                  })
                  .then(() => {
                    console.log('✅ Database initialized successfully');
                    resolve(true);
                  })
                  .catch((migrateErr) => {
                    console.error('❌ Error during migration or FTS init:', migrateErr);
                    // Продолжаем работу даже при ошибке
                    console.log('✅ Database initialized (with warnings)');
                    resolve(true);
                  });
              });
            }
          });
        });
      });
    } catch (error) {
      console.error('❌ Error initializing database:', error);
      reject(error);
    }
  });
}

// Сохранение сообщения в базу данных
export function saveMessage(role, content, sessionId = null, isSummarization = false, tokenCount = null) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => saveMessage(role, content, sessionId, isSummarization, tokenCount).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    // Не сохраняем сообщения с isSummarization = true в LTM
    if (isSummarization === true || isSummarization === 1) {
      resolve({
        success: false,
        error: 'Summarization messages are not saved to LTM',
        skipped: true
      });
      return;
    }
    
    const stmt = db.prepare('INSERT INTO messages (role, content, session_id, is_summarization, token_count) VALUES (?, ?, ?, ?, ?)');
    
    stmt.run([role, content, sessionId, isSummarization ? 1 : 0, tokenCount], function(err) {
      stmt.finalize();
      
      if (err) {
        console.error('❌ Error saving message:', err);
        resolve({
          success: false,
          error: err.message
        });
      } else {
        resolve({
          success: true,
          id: this.lastID
        });
      }
    });
  });
}

// Получение сообщений с пагинацией
export function getMessages(limit = 100, offset = 0, sessionId = null) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getMessages(limit, offset, sessionId).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    let query = 'SELECT * FROM messages';
    const params = [];
    
    if (sessionId) {
      query += ' WHERE session_id = ?';
      params.push(sessionId);
    }
    
    query += ' ORDER BY timestamp ASC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    db.all(query, params, (err, rows) => {
      if (err) {
        console.error('❌ Error getting messages:', err);
        resolve({
          success: false,
          error: err.message,
          messages: []
        });
      } else {
        resolve({
          success: true,
          messages: rows
        });
      }
    });
  });
}

// Поиск сообщений по содержимому
export function searchMessages(query, limit = 50) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => searchMessages(query, limit).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    const searchPattern = `%${query}%`;
    const sql = 'SELECT * FROM messages WHERE content LIKE ? ORDER BY timestamp DESC LIMIT ?';
    
    db.all(sql, [searchPattern, limit], (err, rows) => {
      if (err) {
        console.error('❌ Error searching messages:', err);
        resolve({
          success: false,
          error: err.message,
          messages: []
        });
      } else {
        resolve({
          success: true,
          messages: rows
        });
      }
    });
  });
}

// Очистка всех сообщений
export function clearMessages() {
  return new Promise((resolve, reject) => {
    const executeClear = () => {
      if (!db) {
        console.error('❌ Database not initialized');
        resolve({
          success: false,
          error: 'Database not initialized'
        });
        return;
      }
      
      console.log('🗑️ Clearing all messages from database...');
      
      // Сначала получаем количество сообщений для логирования
      db.get('SELECT COUNT(*) as count FROM messages', (err, row) => {
        if (err) {
          console.error('❌ Error getting message count before clear:', err);
          resolve({
            success: false,
            error: err.message
          });
          return;
        }
        
        const countBefore = row ? row.count : 0;
        console.log(`📊 Messages in database before clear: ${countBefore}`);
        
        if (countBefore === 0) {
          console.log('ℹ️ Database is already empty');
          resolve({
            success: true,
            deletedCount: 0
          });
          return;
        }
        
        // Выполняем удаление
        db.run('DELETE FROM messages', function(err) {
          if (err) {
            console.error('❌ Error clearing messages:', err);
            resolve({
              success: false,
              error: err.message
            });
            return;
          }
          
          const deletedCount = this.changes;
          console.log(`✅ Cleared ${deletedCount} messages from database`);
          
          // Проверяем, что действительно удалилось
          db.get('SELECT COUNT(*) as count FROM messages', (checkErr, checkRow) => {
            if (checkErr) {
              console.error('❌ Error verifying clear:', checkErr);
              // Все равно возвращаем успех, так как DELETE выполнился
              resolve({
                success: true,
                deletedCount: deletedCount
              });
            } else {
              const countAfter = checkRow ? checkRow.count : 0;
              console.log(`📊 Messages in database after clear: ${countAfter}`);
              
              if (countAfter > 0) {
                console.warn(`⚠️ Warning: ${countAfter} messages still remain after clear operation`);
                // Пытаемся удалить еще раз
                db.run('DELETE FROM messages', function(retryErr) {
                  if (retryErr) {
                    console.error('❌ Error on retry clear:', retryErr);
                  } else {
                    console.log(`🔄 Retry clear: deleted ${this.changes} more messages`);
                  }
                  resolve({
                    success: true,
                    deletedCount: deletedCount + (this.changes || 0)
                  });
                });
              } else {
                resolve({
                  success: true,
                  deletedCount: deletedCount
                });
              }
            }
          });
        });
      });
    };
    
    if (!db) {
      initDatabase()
        .then(() => executeClear())
        .catch((err) => {
          console.error('❌ Error initializing database for clear:', err);
          resolve({
            success: false,
            error: err.message
          });
        });
    } else {
      executeClear();
    }
  });
}

// Получение количества сообщений
export function getMessageCount(sessionId = null) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getMessageCount(sessionId).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    let query = 'SELECT COUNT(*) as count FROM messages';
    const params = [];
    
    if (sessionId) {
      query += ' WHERE session_id = ?';
      params.push(sessionId);
    }
    
    db.get(query, params, (err, row) => {
      if (err) {
        console.error('❌ Error getting message count:', err);
        resolve({
          success: false,
          error: err.message,
          count: 0
        });
      } else {
        resolve({
          success: true,
          count: row ? row.count : 0
        });
      }
    });
  });
}

// Получение последних N сообщений
export function getRecentMessages(count = 10, sessionId = null) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getRecentMessages(count, sessionId).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    let query = 'SELECT * FROM messages';
    const params = [];
    
    if (sessionId) {
      query += ' WHERE session_id = ?';
      params.push(sessionId);
    }
    
    query += ' ORDER BY timestamp DESC LIMIT ?';
    params.push(count);
    
    db.all(query, params, (err, rows) => {
      if (err) {
        console.error('❌ Error getting recent messages:', err);
        resolve({
          success: false,
          error: err.message,
          messages: []
        });
      } else {
        // Возвращаем в хронологическом порядке (старые первыми)
        resolve({
          success: true,
          messages: rows.reverse()
        });
      }
    });
  });
}

// Получение сообщений по диапазону ID
export function getMessagesByIdRange(minId, maxId) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getMessagesByIdRange(minId, maxId).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    const query = 'SELECT * FROM messages WHERE id >= ? AND id <= ? ORDER BY id ASC';
    
    db.all(query, [minId, maxId], (err, rows) => {
      if (err) {
        console.error('❌ Error getting messages by ID range:', err);
        resolve({
          success: false,
          error: err.message,
          messages: []
        });
      } else {
        resolve({
          success: true,
          messages: rows
        });
      }
    });
  });
}

// Получение диапазона ID сообщений (min и max)
export function getMessageIdRange() {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getMessageIdRange().then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    const query = 'SELECT MIN(id) as minId, MAX(id) as maxId FROM messages';
    
    db.get(query, [], (err, row) => {
      if (err) {
        console.error('❌ Error getting message ID range:', err);
        resolve({
          success: false,
          error: err.message,
          minId: null,
          maxId: null
        });
      } else {
        resolve({
          success: true,
          minId: row ? row.minId : null,
          maxId: row ? row.maxId : null
        });
      }
    });
  });
}

// Закрытие соединения с базой данных
export function closeDatabase() {
  return new Promise((resolve, reject) => {
    if (db) {
      db.close((err) => {
        if (err) {
          console.error('❌ Error closing database:', err);
          reject(err);
        } else {
          console.log('✅ Database connection closed');
          db = null;
          resolve();
        }
      });
    } else {
      resolve();
    }
  });
}

// Безопасная миграция базы данных
function migrateDatabase() {
  return new Promise((resolve, reject) => {
    if (!db) {
      reject(new Error('Database not initialized'));
      return;
    }
    
    // Проверяем существование полей через PRAGMA table_info
    db.all("PRAGMA table_info(messages)", (err, columns) => {
      if (err) {
        console.error('❌ Error checking table structure:', err);
        resolve(false);
        return;
      }
      
      const columnNames = columns.map(col => col.name);
      const needsIsSummarization = !columnNames.includes('is_summarization');
      const needsTokenCount = !columnNames.includes('token_count');
      
      if (!needsIsSummarization && !needsTokenCount) {
        console.log('✅ Database schema is up to date');
        resolve(true);
        return;
      }
      
      console.log('🔄 Migrating database schema...');
      
      // Добавляем недостающие поля
      const migrations = [];
      
      if (needsIsSummarization) {
        migrations.push(
          new Promise((resolveMig, rejectMig) => {
            db.run('ALTER TABLE messages ADD COLUMN is_summarization INTEGER DEFAULT 0', (err) => {
              if (err) {
                console.error('❌ Error adding is_summarization column:', err);
                rejectMig(err);
              } else {
                console.log('✅ Added is_summarization column');
                resolveMig(true);
              }
            });
          })
        );
      }
      
      if (needsTokenCount) {
        migrations.push(
          new Promise((resolveMig, rejectMig) => {
            db.run('ALTER TABLE messages ADD COLUMN token_count INTEGER', (err) => {
              if (err) {
                console.error('❌ Error adding token_count column:', err);
                rejectMig(err);
              } else {
                console.log('✅ Added token_count column');
                resolveMig(true);
              }
            });
          })
        );
      }
      
      // Выполняем все миграции
      Promise.all(migrations)
        .then(() => {
          // Добавляем индексы если их нет
          const indexPromises = [];
          
          if (needsIsSummarization) {
            indexPromises.push(
              new Promise((resolveIdx, rejectIdx) => {
                db.run('CREATE INDEX IF NOT EXISTS idx_is_summarization ON messages(is_summarization)', (err) => {
                  if (err) {
                    console.warn('⚠️ Error creating index for is_summarization:', err);
                  } else {
                    console.log('✅ Created index for is_summarization');
                  }
                  resolveIdx(true);
                });
              })
            );
          }
          
          if (needsTokenCount) {
            indexPromises.push(
              new Promise((resolveIdx, rejectIdx) => {
                db.run('CREATE INDEX IF NOT EXISTS idx_token_count ON messages(token_count)', (err) => {
                  if (err) {
                    console.warn('⚠️ Error creating index for token_count:', err);
                  } else {
                    console.log('✅ Created index for token_count');
                  }
                  resolveIdx(true);
                });
              })
            );
          }
          
          return Promise.all(indexPromises);
        })
        .then(() => {
          // Обновляем существующие записи: устанавливаем is_summarization = 0 для всех
          db.run('UPDATE messages SET is_summarization = 0 WHERE is_summarization IS NULL', (err) => {
            if (err) {
              console.warn('⚠️ Error updating is_summarization for existing records:', err);
            } else {
              console.log('✅ Updated is_summarization for existing records');
            }
            resolve(true);
          });
        })
        .catch((migrateErr) => {
          console.error('❌ Migration error:', migrateErr);
          resolve(false); // Продолжаем работу даже при ошибке миграции
        });
    });
  });
}

// Инициализация FTS таблицы
function initFTS() {
  return new Promise((resolve, reject) => {
    if (!db) {
      reject(new Error('Database not initialized'));
      return;
    }
    
    // Создаем виртуальную таблицу FTS5 для полнотекстового поиска
    db.exec(`
      CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
        content,
        role,
        id UNINDEXED,
        timestamp UNINDEXED,
        session_id UNINDEXED,
        content='messages',
        content_rowid='id'
      );
      
      -- Триггеры для автоматической синхронизации при INSERT
      CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages BEGIN
        INSERT INTO messages_fts(rowid, content, role) 
        VALUES (new.id, new.content, new.role);
      END;
      
      -- Триггеры для автоматической синхронизации при DELETE
      CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN
        DELETE FROM messages_fts WHERE rowid = old.id;
      END;
      
      -- Триггеры для автоматической синхронизации при UPDATE
      CREATE TRIGGER IF NOT EXISTS messages_fts_update AFTER UPDATE ON messages BEGIN
        DELETE FROM messages_fts WHERE rowid = old.id;
        INSERT INTO messages_fts(rowid, content, role) 
        VALUES (new.id, new.content, new.role);
      END;
    `, (err) => {
      if (err) {
        // Если FTS5 не поддерживается, выводим предупреждение, но не останавливаем работу
        if (err.message.includes('no such module: fts5')) {
          console.warn('⚠️ FTS5 module not available. Full-text search will be disabled.');
          console.warn('   To enable FTS5, recompile SQLite with FTS5 support.');
          resolve(false); // Разрешаем, но возвращаем false
        } else {
          console.error('❌ Error creating FTS table:', err);
          reject(err);
        }
        return;
      }
      
      console.log('✅ FTS table initialized successfully');
      
      // Проверяем, нужно ли заполнить FTS таблицу существующими данными
      db.get('SELECT COUNT(*) as fts_count FROM messages_fts', (countErr, ftsRow) => {
        if (countErr) {
          console.warn('⚠️ Could not check FTS table count:', countErr);
          resolve(true);
          return;
        }
        
        db.get('SELECT COUNT(*) as msg_count FROM messages', (msgErr, msgRow) => {
          if (msgErr) {
            console.warn('⚠️ Could not check messages count:', msgErr);
            resolve(true);
            return;
          }
          
          const ftsCount = ftsRow ? ftsRow.fts_count : 0;
          const msgCount = msgRow ? msgRow.msg_count : 0;
          
          // Если в FTS таблице меньше сообщений, чем в основной, переиндексируем
          if (ftsCount < msgCount && msgCount > 0) {
            console.log(`🔄 Migrating existing messages to FTS (${msgCount - ftsCount} messages to index)...`);
            rebuildFTS()
              .then((result) => {
                if (result.success) {
                  console.log(`✅ Migration completed: ${result.indexedCount} messages indexed`);
                } else {
                  console.warn('⚠️ Migration had errors:', result.error);
                }
                resolve(true);
              })
              .catch((migrateErr) => {
                console.warn('⚠️ Migration error:', migrateErr);
                resolve(true); // Продолжаем работу даже при ошибке миграции
              });
          } else {
            resolve(true);
          }
        });
      });
    });
  });
}

// Поиск релевантных сообщений через FTS
export function searchRelevantMessages(query, limit = 20) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => searchRelevantMessages(query, limit).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    // Проверяем, существует ли FTS таблица
    db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='messages_fts'", (err, row) => {
      if (err) {
        console.error('❌ Error checking FTS table:', err);
        resolve({
          success: false,
          error: err.message,
          messages: []
        });
        return;
      }
      
      if (!row) {
        // FTS таблица не существует, возвращаем пустой результат
        console.warn('⚠️ FTS table does not exist, returning empty results');
        resolve({
          success: true,
          messages: []
        });
        return;
      }
      
      // Экранируем специальные символы FTS5 в запросе
      // FTS5 использует специальные операторы, поэтому нужно экранировать кавычки
      const escapedQuery = query.replace(/"/g, '""');
      
      // Используем FTS5 для поиска с ранжированием по релевантности
      // bm25() - алгоритм ранжирования Best Match 25
      const sql = `
        SELECT 
          m.id,
          m.role,
          m.content,
          m.timestamp,
          m.session_id,
          bm25(messages_fts) as rank
        FROM messages_fts
        JOIN messages m ON messages_fts.rowid = m.id
        WHERE messages_fts MATCH ?
        ORDER BY rank
        LIMIT ?
      `;
      
      db.all(sql, [escapedQuery, limit], (err, rows) => {
        if (err) {
          console.error('❌ Error searching messages with FTS:', err);
          // Если FTS запрос не работает, пробуем простой LIKE поиск как fallback
          const fallbackPattern = `%${query}%`;
          const fallbackSql = 'SELECT * FROM messages WHERE content LIKE ? ORDER BY timestamp DESC LIMIT ?';
          
          db.all(fallbackSql, [fallbackPattern, limit], (fallbackErr, fallbackRows) => {
            if (fallbackErr) {
              console.error('❌ Error in fallback search:', fallbackErr);
              resolve({
                success: false,
                error: fallbackErr.message,
                messages: []
              });
            } else {
              resolve({
                success: true,
                messages: fallbackRows
              });
            }
          });
          return;
        }
        
        resolve({
          success: true,
          messages: rows
        });
      });
    });
  });
}

// Переиндексация всех сообщений в FTS таблицу (для миграции существующих данных)
export function rebuildFTS() {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => rebuildFTS().then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    // Проверяем, существует ли FTS таблица
    db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='messages_fts'", (err, row) => {
      if (err) {
        console.error('❌ Error checking FTS table:', err);
        resolve({
          success: false,
          error: err.message
        });
        return;
      }
      
      if (!row) {
        // FTS таблица не существует, пытаемся создать
        initFTS()
          .then((ftsSuccess) => {
            if (ftsSuccess) {
              // Рекурсивно вызываем rebuildFTS после создания таблицы
              rebuildFTS().then(resolve).catch(reject);
            } else {
              resolve({
                success: false,
                error: 'FTS table could not be created'
              });
            }
          })
          .catch(reject);
      } else {
        // FTS таблица существует, очищаем и перезаполняем
        db.run('DELETE FROM messages_fts', (deleteErr) => {
          if (deleteErr) {
            console.error('❌ Error clearing FTS table:', deleteErr);
            resolve({
              success: false,
              error: deleteErr.message
            });
            return;
          }
          
          // Заполняем FTS таблицу всеми существующими сообщениями
          db.run(`
            INSERT INTO messages_fts(rowid, content, role)
            SELECT id, content, role FROM messages
          `, function(insertErr) {
            if (insertErr) {
              console.error('❌ Error rebuilding FTS table:', insertErr);
              resolve({
                success: false,
                error: insertErr.message
              });
            } else {
              console.log(`✅ Rebuilt FTS table with ${this.changes} messages`);
              resolve({
                success: true,
                indexedCount: this.changes
              });
            }
          });
        });
      }
    });
  });
}

// Получение сообщений из LTM с учетом лимита токенов и offset по накопленным токенам
export function getLTMessagesByTokens(maxTokens, offsetTokens = 0) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getLTMessagesByTokens(maxTokens, offsetTokens).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    // Используем подзапрос для вычисления накопленных токенов
    // Сортируем по timestamp ASC (старые первыми) для правильного накопления
    const sql = `
      WITH cumulative_messages AS (
        SELECT 
          id,
          role,
          content,
          timestamp,
          session_id,
          is_summarization,
          token_count,
          COALESCE(SUM(token_count) OVER (
            ORDER BY timestamp ASC, id ASC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ), 0) as cumulative_tokens
        FROM messages
        WHERE is_summarization = 0 AND token_count IS NOT NULL
      )
      SELECT 
        id,
        role,
        content,
        timestamp,
        session_id,
        is_summarization,
        token_count,
        cumulative_tokens
      FROM cumulative_messages
      WHERE cumulative_tokens > ? 
        AND cumulative_tokens <= ? + ?
      ORDER BY timestamp ASC, id ASC
    `;
    
    db.all(sql, [offsetTokens, offsetTokens, maxTokens], (err, rows) => {
      if (err) {
        console.error('❌ Error getting LTM messages by tokens:', err);
        resolve({
          success: false,
          error: err.message,
          messages: [],
          totalTokens: 0,
          hasMore: false
        });
        return;
      }
      
      // Вычисляем общее количество токенов в результате
      const totalTokens = rows.length > 0 
        ? (rows[rows.length - 1].cumulative_tokens || 0)
        : offsetTokens;
      
      // Проверяем, есть ли еще сообщения после этой пачки
      const lastCumulative = rows.length > 0 
        ? (rows[rows.length - 1].cumulative_tokens || 0)
        : offsetTokens;
      
      // Проверяем, есть ли еще сообщения
      db.get(`
        SELECT COUNT(*) as count
        FROM (
          SELECT 
            COALESCE(SUM(token_count) OVER (
              ORDER BY timestamp ASC, id ASC 
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ), 0) as cumulative_tokens
          FROM messages
          WHERE is_summarization = 0 AND token_count IS NOT NULL
        )
        WHERE cumulative_tokens > ?
      `, [lastCumulative], (hasMoreErr, hasMoreRow) => {
        const hasMore = hasMoreRow && hasMoreRow.count > 0;
        
        resolve({
          success: true,
          messages: rows,
          totalTokens: totalTokens,
          hasMore: hasMore
        });
      });
    });
  });
}

// Поиск сообщений по содержимому с учетом лимита токенов и offset по токенам
export function searchLTMessagesByTokens(query, maxTokens, offsetTokens = 0) {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => searchLTMessagesByTokens(query, maxTokens, offsetTokens).then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    // Разбиваем запрос на слова и ищем каждое слово отдельно
    // Это позволяет находить сообщения, где слова могут быть в разных местах
    const words = query.trim().split(/\s+/).filter(w => w.length > 0);
    
    // Создаем условия для поиска каждого слова
    const likeConditions = words.map(() => 'content LIKE ?').join(' AND ');
    const searchPatterns = words.map(word => `%${word}%`);
    
    console.log(`🔍 LTM search: query="${query}", words=[${words.join(', ')}], patterns=[${searchPatterns.join(', ')}]`);
    
    // Если запрос пустой или нет слов, возвращаем пустой результат
    if (words.length === 0) {
      console.log('⚠️ Empty search query, returning empty results');
      resolve({
        success: true,
        messages: [],
        totalTokens: offsetTokens,
        hasMore: false
      });
      return;
    }
    
    // Используем подзапрос для поиска и вычисления накопленных токенов
    const sql = `
      WITH filtered_messages AS (
        SELECT 
          id,
          role,
          content,
          timestamp,
          session_id,
          is_summarization,
          token_count
        FROM messages
        WHERE ${likeConditions}
          AND is_summarization = 0 
          AND token_count IS NOT NULL
      ),
      cumulative_messages AS (
        SELECT 
          *,
          COALESCE(SUM(token_count) OVER (
            ORDER BY timestamp ASC, id ASC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ), 0) as cumulative_tokens
        FROM filtered_messages
      )
      SELECT 
        id,
        role,
        content,
        timestamp,
        session_id,
        is_summarization,
        token_count,
        cumulative_tokens
      FROM cumulative_messages
      WHERE cumulative_tokens > ? 
        AND cumulative_tokens <= ? + ?
      ORDER BY timestamp ASC, id ASC
    `;
    
      db.all(sql, [...searchPatterns, offsetTokens, offsetTokens, maxTokens], (err, rows) => {
        if (err) {
          console.error('❌ Error searching LTM messages by tokens:', err);
          console.error('   SQL:', sql);
          console.error('   Params:', [...searchPatterns, offsetTokens, offsetTokens, maxTokens]);
          resolve({
            success: false,
            error: err.message,
            messages: [],
            totalTokens: 0,
            hasMore: false
          });
          return;
        }
        
        // Вычисляем общее количество токенов в результате
        const totalTokens = rows.length > 0 
          ? (rows[rows.length - 1].cumulative_tokens || 0)
          : offsetTokens;
        
        console.log(`📊 LTM search results: found ${rows.length} messages (offset: ${offsetTokens}, total tokens: ${totalTokens})`);
        if (rows.length > 0) {
          console.log(`   First message ID: ${rows[0].id}, Last message ID: ${rows[rows.length - 1].id}`);
        }
        
        // Проверяем, есть ли еще сообщения после этой пачки
        const lastCumulative = rows.length > 0 
          ? (rows[rows.length - 1].cumulative_tokens || 0)
          : offsetTokens;
      
      // Проверяем, есть ли еще сообщения с таким же запросом
      const hasMoreSql = `
        SELECT COUNT(*) as count
        FROM (
          SELECT 
            COALESCE(SUM(token_count) OVER (
              ORDER BY timestamp ASC, id ASC 
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ), 0) as cumulative_tokens
          FROM messages
          WHERE ${likeConditions}
            AND is_summarization = 0 
            AND token_count IS NOT NULL
        )
        WHERE cumulative_tokens > ?
      `;
      
      db.get(hasMoreSql, [...searchPatterns, lastCumulative], (hasMoreErr, hasMoreRow) => {
        const hasMore = hasMoreRow && hasMoreRow.count > 0;
        
        resolve({
          success: true,
          messages: rows,
          totalTokens: totalTokens,
          hasMore: hasMore
        });
      });
    });
  });
}

// Получение количества сообщений в LTM (исключая суммаризации)
export function getLTMessagesCount() {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getLTMessagesCount().then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    const query = 'SELECT COUNT(*) as count FROM messages WHERE is_summarization = 0';
    
    db.get(query, [], (err, row) => {
      if (err) {
        console.error('❌ Error getting LTM messages count:', err);
        resolve({
          success: false,
          error: err.message,
          count: 0
        });
      } else {
        resolve({
          success: true,
          count: row ? row.count : 0
        });
      }
    });
  });
}

// Получение общего количества токенов в LTM
export function getLTMTotalTokens() {
  return new Promise((resolve, reject) => {
    if (!db) {
      initDatabase()
        .then(() => getLTMTotalTokens().then(resolve).catch(reject))
        .catch(reject);
      return;
    }
    
    const query = 'SELECT SUM(token_count) as total FROM messages WHERE is_summarization = 0 AND token_count IS NOT NULL';
    
    db.get(query, [], (err, row) => {
      if (err) {
        console.error('❌ Error getting LTM total tokens:', err);
        resolve({
          success: false,
          error: err.message,
          total: 0
        });
      } else {
        resolve({
          success: true,
          total: row && row.total ? row.total : 0
        });
      }
    });
  });
}

// Инициализация при импорте модуля
initDatabase().catch(err => {
  console.error('❌ Failed to initialize database on import:', err);
});
