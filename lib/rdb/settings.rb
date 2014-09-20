require 'json'
require 'hashery/open_cascade'
require 'fileutils'

module Rdb
  class Settings
    def initialize
      @settings = Hashery::OpenCascade.new
    end

    def include(obj)
      case obj
      when String
        include_file(obj)
      when Hash
        include_hash(obj)
      end
    end

    def save(file)
      dir = File.dirname(file)
      if !Dir.exist?(dir)
        FileUtils.mkdir_p(dir)
      end

      File.write(file, JSON.pretty_generate(@settings))
    end

    def method_missing(sym, *args, &block)
      @settings.send(sym, *args, &block)
    end

    private

    def include_file(file)
      return if !File.exist?(file)

      content = File.read(file)
      settings = JSON.parse(content, symbolize_names: true)
      include_hash(settings)
    end

    def include_hash(hash)
      merge!(@settings, hash)
    end

    def merge!(left, right)
      keys = (left.keys + right.keys).uniq
      keys.each do |key|
        lvalue, rvalue = left[key], right[key]
        if lvalue.nil?
          left[key] = rvalue
        elsif !rvalue.nil?
          if rvalue.is_a? Hash
            if lvalue.is_a? Hash
              merge!(lvalue, rvalue)
            else
              left[key] = rvalue
            end
          else
            left[key] = rvalue
          end
        end
      end

      left
    end
  end

  class AppSettings < Settings
    def initialize(overrides = {})
      super()
      self.include(DEFAULTS)
      self.include(FILE)
      self.include(ENV)
      self.include(overrides)
    end

    def save!
      save(FILE)
    end

    DEFAULTS = {
      web: {
        host: 'localhost',
        port: 4567
      }
    }

    ENV = {
      web: {
        host: ENV['RDB_HOST'],
        port: ENV['RDB_PORT']
      }
    }

    FILE = File.join(Dir.home, '.rdb', 'settings.json')
  end
