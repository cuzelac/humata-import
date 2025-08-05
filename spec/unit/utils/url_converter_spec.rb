# frozen_string_literal: true

require 'spec_helper'

module HumataImport
  module Utils
    describe UrlConverter do
      describe '.google_drive_url?' do
        it 'identifies Google Drive URLs' do
          _(UrlConverter.google_drive_url?('https://drive.google.com/file/d/123/view')).must_equal true
          _(UrlConverter.google_drive_url?('https://docs.google.com/document/d/123/edit')).must_equal true
          _(UrlConverter.google_drive_url?('https://example.com/file.pdf')).must_equal false
          _(UrlConverter.google_drive_url?(nil)).must_equal false
        end
      end

      describe '.extract_file_id' do
        it 'extracts file IDs from various Google Drive URL formats' do
          # File URLs
          _(UrlConverter.extract_file_id('https://drive.google.com/file/d/abc123/view?usp=sharing')).must_equal 'abc123'
          _(UrlConverter.extract_file_id('https://drive.google.com/file/d/def456/edit')).must_equal 'def456'
          
          # Document URLs
          _(UrlConverter.extract_file_id('https://docs.google.com/document/d/ghi789/edit?usp=sharing')).must_equal 'ghi789'
          
          # Spreadsheet URLs
          _(UrlConverter.extract_file_id('https://docs.google.com/spreadsheets/d/jkl012/edit')).must_equal 'jkl012'
          
          # Presentation URLs
          _(UrlConverter.extract_file_id('https://docs.google.com/presentation/d/mno345/edit')).must_equal 'mno345'
          
          # Query parameter URLs
          _(UrlConverter.extract_file_id('https://drive.google.com/uc?id=pqr678&export=download')).must_equal 'pqr678'
          _(UrlConverter.extract_file_id('https://drive.google.com/open?id=stu901')).must_equal 'stu901'
          
          # Non-Google Drive URLs
          _(UrlConverter.extract_file_id('https://example.com/file.pdf')).must_be_nil
        end
      end

      describe '.convert_google_drive_url' do
        it 'converts Google Drive URLs to direct download format' do
          original = 'https://drive.google.com/file/d/abc123/view?usp=sharing'
          expected = 'https://drive.google.com/uc?id=abc123&export=download'
          _(UrlConverter.convert_google_drive_url(original)).must_equal expected
        end

        it 'leaves non-Google Drive URLs unchanged' do
          url = 'https://example.com/file.pdf'
          _(UrlConverter.convert_google_drive_url(url)).must_equal url
        end

        it 'handles URLs without file IDs' do
          url = 'https://drive.google.com/drive/folders/123'
          _(UrlConverter.convert_google_drive_url(url)).must_equal url
        end
      end

      describe '.sanitize_url' do
        it 'removes problematic query parameters' do
          original = 'https://example.com/file.pdf?usp=sharing&edit=true&view=1&param=value'
          expected = 'https://example.com/file.pdf?param=value'
          _(UrlConverter.sanitize_url(original)).must_equal expected
        end

        it 'removes fragments' do
          original = 'https://example.com/file.pdf#section1'
          expected = 'https://example.com/file.pdf'
          _(UrlConverter.sanitize_url(original)).must_equal expected
        end

        it 'handles URLs without query parameters' do
          url = 'https://example.com/file.pdf'
          _(UrlConverter.sanitize_url(url)).must_equal url
        end
      end

      describe '.optimize_for_humata' do
        it 'combines sanitization and Google Drive conversion' do
          original = 'https://drive.google.com/file/d/abc123/view?usp=sharing#section1'
          expected = 'https://drive.google.com/uc?id=abc123&export=download'
          _(UrlConverter.optimize_for_humata(original)).must_equal expected
        end

        it 'handles non-Google Drive URLs' do
          original = 'https://example.com/file.pdf?usp=sharing#section1'
          expected = 'https://example.com/file.pdf'
          _(UrlConverter.optimize_for_humata(original)).must_equal expected
        end
      end
    end
  end
end 