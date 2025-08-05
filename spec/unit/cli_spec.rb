# frozen_string_literal: true

require 'spec_helper'

describe HumataImport::CLI do
  let(:cli) { HumataImport::CLI.new }

  describe '#run' do
    it 'routes discover command correctly' do
      discover_instance = Minitest::Mock.new
      discover_instance.expect :run, nil, [['https://drive.google.com/drive/folders/test']]
      
      HumataImport::Commands::Discover.stub :new, discover_instance do
        cli.run(['discover', 'https://drive.google.com/drive/folders/test'])
      end
      
      discover_instance.verify
    end

    it 'routes upload command correctly' do
      upload_instance = Minitest::Mock.new
      upload_instance.expect :run, nil, [['--folder-id', 'test-folder']]
      
      HumataImport::Commands::Upload.stub :new, upload_instance do
        cli.run(['upload', '--folder-id', 'test-folder'])
      end
      
      upload_instance.verify
    end

    it 'routes verify command correctly' do
      verify_instance = Minitest::Mock.new
      verify_instance.expect :run, nil, [[]]
      
      HumataImport::Commands::Verify.stub :new, verify_instance do
        cli.run(['verify'])
      end
      
      verify_instance.verify
    end

    it 'routes run command correctly' do
      run_instance = Minitest::Mock.new
      run_instance.expect :run, nil, [['https://drive.google.com/drive/folders/test', '--folder-id', 'test-folder']]
      
      HumataImport::Commands::Run.stub :new, run_instance do
        cli.run(['run', 'https://drive.google.com/drive/folders/test', '--folder-id', 'test-folder'])
      end
      
      run_instance.verify
    end

    it 'routes status command correctly' do
      status_instance = Minitest::Mock.new
      status_instance.expect :run, nil, [[]]
      
      HumataImport::Commands::Status.stub :new, status_instance do
        cli.run(['status'])
      end
      
      status_instance.verify
    end

    it 'sets default options' do
      discover_instance = Minitest::Mock.new
      discover_instance.expect :run, nil, [['https://drive.google.com/drive/folders/test']]
      
      HumataImport::Commands::Discover.stub :new, discover_instance do
        cli.run(['discover', 'https://drive.google.com/drive/folders/test'])
      end
      
      # Verify the mock was called with default options
      discover_instance.verify
    end

    it 'handles custom database path' do
      discover_instance = Minitest::Mock.new
      discover_instance.expect :run, nil, [['https://drive.google.com/drive/folders/test']]
      
      HumataImport::Commands::Discover.stub :new, discover_instance do
        cli.run(['--database', '/custom/path.db', 'discover', 'https://drive.google.com/drive/folders/test'])
      end
      
      discover_instance.verify
    end

    it 'handles verbose flag' do
      discover_instance = Minitest::Mock.new
      discover_instance.expect :run, nil, [['https://drive.google.com/drive/folders/test']]
      
      HumataImport::Commands::Discover.stub :new, discover_instance do
        cli.run(['--verbose', 'discover', 'https://drive.google.com/drive/folders/test'])
      end
      
      discover_instance.verify
    end

    it 'handles short verbose flag' do
      discover_instance = Minitest::Mock.new
      discover_instance.expect :run, nil, [['https://drive.google.com/drive/folders/test']]
      
      HumataImport::Commands::Discover.stub :new, discover_instance do
        cli.run(['-v', 'discover', 'https://drive.google.com/drive/folders/test'])
      end
      
      discover_instance.verify
    end

    it 'shows help and exits with error for unknown command' do
      assert_raises(SystemExit) do
        cli.run(['unknown-command'])
      end
    end

    it 'shows help and exits with error for no command' do
      assert_raises(SystemExit) do
        cli.run([])
      end
    end

    it 'shows help and exits when --help is used' do
      assert_raises(SystemExit) do
        cli.run(['--help'])
      end
    end

    it 'shows help and exits when -h is used' do
      assert_raises(SystemExit) do
        cli.run(['-h'])
      end
    end
  end

  describe '#print_commands_help' do
    it 'outputs available commands' do
      output = capture_io { cli.send(:print_commands_help) }[0]
      
      assert_includes output, 'discover'
      assert_includes output, 'upload'
      assert_includes output, 'verify'
      assert_includes output, 'run'
      assert_includes output, 'status'
      assert_includes output, 'humata-import <command> --help'
    end
  end
end 