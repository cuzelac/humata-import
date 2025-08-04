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
    before do
      @service_mock = OpenStruct.new
      client.instance_variable_set(:@service, @service_mock)
      client.instance_variable_set(:@auth_mock, Minitest::Mock.new)
    end

    it 'lists files in a folder' do
      mock_files = [
        { id: 'file1', name: 'test1.pdf', mime_type: 'application/pdf' },
        { id: 'file2', name: 'test2.doc', mime_type: 'application/msword' }
      ]
      
      @service_mock.define_singleton_method(:list_files) do |params|
        OpenStruct.new(
          files: mock_files.map do |f|
            OpenStruct.new(
              id: f[:id],
              name: f[:name],
              mime_type: f[:mime_type],
              web_content_link: "https://drive.google.com/uc?id=#{f[:id]}",
              size: 1024
            )
          end,
          next_page_token: nil
        )
      end

      files = client.list_files(folder_url)
      _(files.size).must_equal 2
      _(files.first[:id]).must_equal 'file1'
      _(files.first[:name]).must_equal 'test1.pdf'
    end

    it 'handles API errors gracefully' do
      @service_mock.define_singleton_method(:list_files) do |params|
        raise Google::Apis::Error, 'API error'
      end

      files = client.list_files(folder_url)
      _(files).must_be_empty
    end

    it 'recursively lists files in subfolders when recursive is true' do
      folder_files = [
        { id: 'file1', name: 'test1.pdf', mime_type: 'application/pdf' },
        { id: 'subfolder', name: 'subfolder', mime_type: 'application/vnd.google-apps.folder' }
      ]
      
      subfolder_files = [
        { id: 'file2', name: 'test2.pdf', mime_type: 'application/pdf' }
      ]

      call_count = 0
      @service_mock.define_singleton_method(:list_files) do |params|
        call_count += 1
        if call_count == 1
          OpenStruct.new(
            files: folder_files.map do |f|
              OpenStruct.new(
                id: f[:id],
                name: f[:name],
                mime_type: f[:mime_type],
                web_content_link: "https://drive.google.com/uc?id=#{f[:id]}",
                size: 1024
              )
            end,
            next_page_token: nil
          )
        else
          OpenStruct.new(
            files: subfolder_files.map do |f|
              OpenStruct.new(
                id: f[:id],
                name: f[:name],
                mime_type: f[:mime_type],
                web_content_link: "https://drive.google.com/uc?id=#{f[:id]}",
                size: 1024
              )
            end,
            next_page_token: nil
          )
        end
      end

      files = client.list_files(folder_url, recursive: true)
      _(files.size).must_equal 2  # 1 file in root + 1 file in subfolder
    end

    it 'only lists files in the root folder when recursive is false' do
      folder_files = [
        { id: 'file1', name: 'test1.pdf', mime_type: 'application/pdf' },
        { id: 'subfolder', name: 'subfolder', mime_type: 'application/vnd.google-apps.folder' }
      ]

      @service_mock.define_singleton_method(:list_files) do |params|
        OpenStruct.new(
          files: folder_files.map do |f|
            OpenStruct.new(
              id: f[:id],
              name: f[:name],
              mime_type: f[:mime_type],
              web_content_link: "https://drive.google.com/uc?id=#{f[:id]}",
              size: 1024
            )
          end,
          next_page_token: nil
        )
      end

      files = client.list_files(folder_url, recursive: false)
      _(files.size).must_equal 1  # Only the PDF file, not the subfolder
      _(files.first[:id]).must_equal 'file1'
    end
  end
end