# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'
require 'minitest/hooks'
require 'fileutils'
require 'sqlite3'
require 'securerandom'
require 'ostruct'
require 'csv'
require 'webmock/minitest'

# Set test environment
ENV['TEST_ENV'] = 'true'

# Load support files
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

# Load the main library
require 'humata_import'

class Minitest::Spec
  include Minitest::Hooks
  
  # Create a temporary database for each test
  def before_all
    super
    @temp_db_path = File.expand_path("../tmp/test_#{SecureRandom.hex(8)}.db", __dir__)
    FileUtils.mkdir_p(File.dirname(@temp_db_path))
    FileUtils.touch(@temp_db_path)
    FileUtils.chmod(0666, @temp_db_path)
    @db = SQLite3::Database.new(@temp_db_path)
    @db.results_as_hash = true
    HumataImport::Database.initialize_schema(@temp_db_path)
    ENV['HUMATA_DB_PATH'] = @temp_db_path
  end

  # Clean up the temporary database
  def after_all
    super
    @db.close
    File.unlink(@temp_db_path) if File.exist?(@temp_db_path)
  end

  # Reset the database before each test
  def before_each
    super
    @db.execute('DELETE FROM file_records')
  end
end