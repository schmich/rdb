require 'rdb/version'
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
 
      bind = options[:host] || 'localhost'
      port = options[:port] || 4567

      server = Rdb::DebugServer
      server.set(:bind, bind)
      server.set(:port, port)
      server.run! do
        Launchy.open("http://localhost:#{port}")
      end
    end

    desc '-v|--version', 'Print version.'
    def version
      puts "rdb #{Rdb::VERSION}"
    end

    default_task :start
  end
end
