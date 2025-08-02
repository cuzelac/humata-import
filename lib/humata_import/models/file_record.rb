require 'sqlite3'

module HumataImport
  class FileRecord
    TABLE = 'file_records'

    def self.create(db, gdrive_id:, name:, url:, **attrs)
      db.execute("INSERT OR IGNORE INTO #{TABLE} (gdrive_id, name, url, size, mime_type, humata_folder_id, upload_status, discovered_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))",
        [gdrive_id, name, url, attrs[:size], attrs[:mime_type], attrs[:humata_folder_id], attrs[:upload_status] || 'pending'])
    end

    def self.find_pending(db)
      db.execute("SELECT * FROM #{TABLE} WHERE upload_status = 'pending'")
    end

    def self.update_status(db, gdrive_id, status)
      db.execute("UPDATE #{TABLE} SET upload_status = ?, last_checked_at = datetime('now') WHERE gdrive_id = ?", [status, gdrive_id])
    end

    def self.all(db)
      db.execute("SELECT * FROM #{TABLE}")
    end
  end
end