# frozen_string_literal: true

require_relative '../../spec_helper'

describe HumataImport::Clients::GdriveClient do
  include TestHelpers
  
  let(:client) do
    # Mock Google Auth
    auth_mock = Minitest::Mock.new
    auth_mock.expect(:authorization=, nil, [nil])
    
    client = HumataImport::Clients::GdriveClient.new
    client.instance_variable_set(:@service, auth_mock)
    client
  end
  let(:folder_url) { 'https://drive.google.com/drive/folders/abc123' }
  let(:folder_id) { 'abc123' }

  describe '#extract_folder_id' do
    it 'extracts folder ID from valid URLs' do
      urls = [
        'https://drive.google.com/drive/folders/abc123',
        'https://drive.google.com/drive/folders/abc123?usp=sharing',
        'https://drive.google.com/drive/folders/abc123/',
        'abc123'  # Already a folder ID
      ]

      urls.each do |url|
        _(client.send(:extract_folder_id, url)).must_equal 'abc123'
      end
    end

    it 'raises ArgumentError for invalid URLs' do
      invalid_urls = [
        'https://drive.google.com/drive/folders/',
        'https://drive.google.com/drive/',
        'https://example.com',
        ''
      ]

      invalid_urls.each do |url|
        _(-> { client.send(:extract_folder_id, url) }).must_raise ArgumentError
      end
    end
  end

  describe '#list_files' do
    it 'lists files from a folder' do
      # Create mock service with injected response
      service_mock = OpenStruct.new
      service_mock.define_singleton_method(:list_files) do |params|
        OpenStruct.new(
          files: [
            OpenStruct.new(
              id: 'file1',
              name: 'test.pdf',
              mime_type: 'application/pdf',
              web_content_link: 'https://example.com/file1',
              size: 1024
            ),
            OpenStruct.new(
              id: 'file2',
              name: 'test.docx',
              mime_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              web_content_link: 'https://example.com/file2',
              size: 2048
            )
          ],
          next_page_token: nil
        )
      end

      client = HumataImport::Clients::GdriveClient.new(service: service_mock)
      files = client.list_files(folder_url)

      _(files.size).must_equal 2
      _(files[0][:id]).must_equal 'file1'
      _(files[0][:name]).must_equal 'test.pdf'
      _(files[0][:mime_type]).must_equal 'application/pdf'
      _(files[1][:id]).must_equal 'file2'
      _(files[1][:name]).must_equal 'test.docx'
    end

    it 'handles recursive folder crawling' do
      # Create mock service with nested folder structure
      service_mock = OpenStruct.new
      call_count = 0
      service_mock.define_singleton_method(:list_files) do |params|
        call_count += 1
        if call_count == 1
          # Root folder contains a subfolder and a file
          OpenStruct.new(
            files: [
              OpenStruct.new(
                id: 'subfolder',
                name: 'Subfolder',
                mime_type: 'application/vnd.google-apps.folder'
              ),
              OpenStruct.new(
                id: 'file1',
                name: 'root.pdf',
                mime_type: 'application/pdf',
                web_content_link: 'https://example.com/root.pdf',
                size: 1024
              )
            ],
            next_page_token: nil
          )
        else
          # Subfolder contains a file
          OpenStruct.new(
            files: [
              OpenStruct.new(
                id: 'file2',
                name: 'sub.pdf',
                mime_type: 'application/pdf',
                web_content_link: 'https://example.com/sub.pdf',
                size: 2048
              )
            ],
            next_page_token: nil
          )
        end
      end

      client = HumataImport::Clients::GdriveClient.new(service: service_mock)
      files = client.list_files(folder_url, recursive: true)

      _(files.size).must_equal 2
      # Check that both files are present, regardless of order
      file_names = files.map { |f| f[:name] }.sort
      _(file_names).must_equal ['root.pdf', 'sub.pdf']
    end

    it 'skips subfolders when recursive is false' do
      # Create mock service with folder structure
      service_mock = OpenStruct.new
      service_mock.define_singleton_method(:list_files) do |params|
        OpenStruct.new(
          files: [
            OpenStruct.new(
              id: 'subfolder',
              name: 'Subfolder',
              mime_type: 'application/vnd.google-apps.folder'
            ),
            OpenStruct.new(
              id: 'file1',
              name: 'root.pdf',
              mime_type: 'application/pdf',
              web_content_link: 'https://example.com/root.pdf',
              size: 1024
            )
          ],
          next_page_token: nil
        )
      end

      client = HumataImport::Clients::GdriveClient.new(service: service_mock)
      files = client.list_files(folder_url, recursive: false)

      _(files.size).must_equal 1
      _(files[0][:name]).must_equal 'root.pdf'
    end

    it 'handles API errors gracefully' do
      # Create mock service that raises an error
      service_mock = OpenStruct.new
      service_mock.define_singleton_method(:list_files) do |params|
        raise Google::Apis::Error, 'API error'
      end

      client = HumataImport::Clients::GdriveClient.new(service: service_mock)
      files = client.list_files(folder_url)

      _(files).must_equal []
    end
  end
end