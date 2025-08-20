# frozen_string_literal: true

require 'spec_helper'

module HumataImport
  module Utils
    describe UrlBuilder do
      describe '.build_humata_url' do
        it 'builds URLs in the correct format' do
          url = UrlBuilder.build_humata_url('abc123', 'document.pdf')
          _(url).must_equal 'https://gdrive-resource.cuzelac.workers.dev/abc123/document.pdf'
        end

        it 'uses default domain when none specified' do
          url = UrlBuilder.build_humata_url('def456', 'spreadsheet.xlsx')
          _(url).must_equal 'https://gdrive-resource.cuzelac.workers.dev/def456/spreadsheet.xlsx'
        end

        it 'allows custom domain' do
          custom_domain = 'https://custom.example.com'
          url = UrlBuilder.build_humata_url('ghi789', 'presentation.pptx', domain: custom_domain)
          _(url).must_equal 'https://custom.example.com/ghi789/presentation.pptx'
        end

        it 'handles domains with trailing slashes' do
          domain_with_slash = 'https://example.com/'
          url = UrlBuilder.build_humata_url('jkl012', 'file.txt', domain: domain_with_slash)
          _(url).must_equal 'https://example.com/jkl012/file.txt'
        end

        it 'raises error for nil file_id' do
          _{ UrlBuilder.build_humata_url(nil, 'file.pdf') }.must_raise ArgumentError
        end

        it 'raises error for empty file_id' do
          _{ UrlBuilder.build_humata_url('', 'file.pdf') }.must_raise ArgumentError
        end

        it 'raises error for nil file_name' do
          _{ UrlBuilder.build_humata_url('abc123', nil) }.must_raise ArgumentError
        end

        it 'raises error for empty file_name' do
          _{ UrlBuilder.build_humata_url('abc123', '') }.must_raise ArgumentError
        end

        it 'raises error for nil domain' do
          _{ UrlBuilder.build_humata_url('abc123', 'file.pdf', domain: nil) }.must_raise ArgumentError
        end

        it 'raises error for empty domain' do
          _{ UrlBuilder.build_humata_url('abc123', 'file.pdf', domain: '') }.must_raise ArgumentError
        end

        it 'handles special characters in file names' do
          url = UrlBuilder.build_humata_url('abc123', 'file with spaces & symbols.pdf')
          _(url).must_equal 'https://gdrive-resource.cuzelac.workers.dev/abc123/file with spaces & symbols.pdf'
        end

        it 'handles file names with dots' do
          url = UrlBuilder.build_humata_url('abc123', 'backup.2024.01.01.pdf')
          _(url).must_equal 'https://gdrive-resource.cuzelac.workers.dev/abc123/backup.2024.01.01.pdf'
        end
      end

      describe '.google_drive_url?' do
        it 'identifies Google Drive URLs' do
          _(UrlBuilder.google_drive_url?('https://drive.google.com/file/d/123/view')).must_equal true
          _(UrlBuilder.google_drive_url?('https://docs.google.com/document/d/123/edit')).must_equal true
          _(UrlBuilder.google_drive_url?('https://example.com/file.pdf')).must_equal false
          _(UrlBuilder.google_drive_url?(nil)).must_equal false
        end
      end

      describe '.extract_file_id' do
        it 'extracts file IDs from various Google Drive URL formats' do
          # File URLs
          _(UrlBuilder.extract_file_id('https://drive.google.com/file/d/abc123/view?usp=sharing')).must_equal 'abc123'
          _(UrlBuilder.extract_file_id('https://drive.google.com/file/d/def456/edit')).must_equal 'def456'
          
          # Document URLs
          _(UrlBuilder.extract_file_id('https://docs.google.com/document/d/ghi789/edit?usp=sharing')).must_equal 'ghi789'
          
          # Spreadsheet URLs
          _(UrlBuilder.extract_file_id('https://docs.google.com/spreadsheets/d/jkl012/edit')).must_equal 'jkl012'
          
          # Presentation URLs
          _(UrlBuilder.extract_file_id('https://docs.google.com/presentation/d/mno345/edit')).must_equal 'mno345'
          
          # Query parameter URLs
          _(UrlBuilder.extract_file_id('https://drive.google.com/uc?id=pqr678&export=download')).must_equal 'pqr678'
          _(UrlBuilder.extract_file_id('https://drive.google.com/open?id=stu901')).must_equal 'stu901'
          
          # Non-Google Drive URLs
          _(UrlBuilder.extract_file_id('https://example.com/file.pdf')).must_be_nil
        end
      end

      describe '.convert_google_drive_url' do
        it 'converts Google Drive URLs to direct file view format' do
          original = 'https://drive.google.com/file/d/abc123/view?usp=sharing'
          expected = 'https://drive.google.com/file/d/abc123/view?usp=drive_link'
          _(UrlBuilder.convert_google_drive_url(original)).must_equal expected
        end

        it 'preserves already correct drive_link format' do
          url = 'https://drive.google.com/file/d/1P46B9iPFw93kUmsAVJcKBtCgPRVjOk8S/view?usp=drive_link'
          _(UrlBuilder.convert_google_drive_url(url)).must_equal url
        end

        it 'leaves non-Google Drive URLs unchanged' do
          url = 'https://example.com/file.pdf'
          _(UrlBuilder.convert_google_drive_url(url)).must_equal url
        end

        it 'handles URLs without file IDs' do
          url = 'https://drive.google.com/drive/folders/123'
          _(UrlBuilder.convert_google_drive_url(url)).must_equal url
        end
      end

      describe '.sanitize_url' do
        it 'removes problematic query parameters' do
          original = 'https://example.com/file.pdf?usp=sharing&edit=true&view=1&param=value'
          expected = 'https://example.com/file.pdf?param=value'
          _(UrlBuilder.sanitize_url(original)).must_equal expected
        end

        it 'preserves usp=drive_link parameter' do
          original = 'https://drive.google.com/file/d/123/view?usp=drive_link&edit=true'
          expected = 'https://drive.google.com/file/d/123/view?usp=drive_link'
          _(UrlBuilder.sanitize_url(original)).must_equal expected
        end

        it 'removes fragments' do
          original = 'https://example.com/file.pdf#section1'
          expected = 'https://example.com/file.pdf'
          _(UrlBuilder.sanitize_url(original)).must_equal expected
        end

        it 'handles URLs without query parameters' do
          url = 'https://example.com/file.pdf'
          _(UrlBuilder.sanitize_url(url)).must_equal url
        end
      end

      describe '.optimize_for_humata' do
        it 'combines sanitization and Google Drive conversion' do
          original = 'https://drive.google.com/file/d/abc123/view?usp=sharing#section1'
          expected = 'https://drive.google.com/file/d/abc123/view?usp=drive_link'
          _(UrlBuilder.optimize_for_humata(original)).must_equal expected
        end

        it 'handles non-Google Drive URLs' do
          original = 'https://example.com/file.pdf?usp=sharing#section1'
          expected = 'https://example.com/file.pdf'
          _(UrlBuilder.optimize_for_humata(original)).must_equal expected
        end
      end

      describe 'integration' do
        it 'can build Humata URLs and optimize Google Drive URLs' do
          # Build a Humata URL
          humata_url = UrlBuilder.build_humata_url('abc123', 'document.pdf')
          _(humata_url).must_equal 'https://gdrive-resource.cuzelac.workers.dev/abc123/document.pdf'
          
          # Optimize a Google Drive URL
          gdrive_url = 'https://drive.google.com/file/d/def456/view?usp=sharing'
          optimized = UrlBuilder.optimize_for_humata(gdrive_url)
          _(optimized).must_equal 'https://drive.google.com/file/d/def456/view?usp=drive_link'
        end
      end
    end
  end
end
