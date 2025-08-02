Gem::Specification.new do |spec|
  spec.name          = 'humata-import'
  spec.version       = '0.1.0'
  spec.authors       = ['Your Name']
  spec.email         = ['your.email@example.com']
  spec.summary       = 'CLI tool to import Google Drive files into Humata.ai'
  spec.description   = 'A Ruby CLI tool for importing publicly accessible Google Drive files into Humata.ai using the Humata API.'
  spec.homepage      = 'https://github.com/yourusername/humata-import'
  spec.license       = 'MIT'

  spec.files         = Dir['lib/**/*.rb'] + ['README.md']
  spec.executables   = ['humata-import']
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'sqlite3', '~> 1.6'
  spec.add_runtime_dependency 'google-api-client', '~> 0.53'
end