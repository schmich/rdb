require 'thor'
require 'launchy'

module Rdb
  class CommandLine < Thor
    desc '[--host <host>] [--port <port>]', 'Start debug server.'
    options :port => :integer, :host => :string
    def start
      bind = options[:host] || 'localhost'
      port = options[:port] || 4567

      server = Rdb::DebugServer
      server.set(:bind, bind)
      server.set(:port, port)
      server.run! do
        Launchy.open("http://localhost:#{port}")
      end
    end

    default_task :start
  end
end
