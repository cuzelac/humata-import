# frozen_string_literal: true

require 'singleton'
require_relative 'humata_import/logger'
require_relative 'humata_import/clients/gdrive_client'
require_relative 'humata_import/clients/humata_client'
require_relative 'humata_import/database'
require_relative 'humata_import/models/file_record'
require_relative 'humata_import/commands/base'
require_relative 'humata_import/commands/discover'
require_relative 'humata_import/commands/run'
require_relative 'humata_import/commands/status'
require_relative 'humata_import/commands/upload'
require_relative 'humata_import/commands/verify'

module HumataImport
  VERSION = "0.1.0"
end