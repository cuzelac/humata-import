require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'spec'
  t.libs << 'lib'
  t.test_files = FileList['spec/**/*_spec.rb']
end

# Set environment variable for verbose tests
task :set_test_verbose do
  ENV['TEST_VERBOSE'] = 'true'
end

# Task for running tests with verbose logging
Rake::TestTask.new(:test_verbose => :set_test_verbose) do |t|
  t.libs << 'spec'
  t.libs << 'lib'
  t.test_files = FileList['spec/**/*_spec.rb']
  # Ensure Minitest runs in verbose mode (per-test names and timings)
  t.options = '-v'
end

task default: :test