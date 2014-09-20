require 'rdb/version'
require 'rdb/settings'
require 'thor'
require 'launchy'

module Rdb
  class CommandLine < Thor
    desc '[--host <host>] [--port <port>]', 'Start debug server.'
    options :port => :integer, :host => :string
    option :version, :type => :boolean, :aliases => :v
    def start
      if options[:version]
        version
        return
      end
 
      settings = AppSettings.new({
        web: {
          host: options[:host],
          port: options[:port]
        }
      })

      server = Rdb::DebugServer
      server.set(:bind, settings.web.host)
      server.set(:port, settings.web.port)
      server.run! do
        Launchy.open("http://localhost:#{settings.web.port}")
      end
    end

    desc '-v|--version', 'Print version.'
    def version
      puts "rdb #{Rdb::VERSION}"
    end

    default_task :start
  end
end
