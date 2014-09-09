require 'byebug'
require 'json'

class Server
  def initialize
    server = TCPServer.new('0.0.0.0', 1234)
    Thread.new do
      begin
        while connection = server.accept
          Thread.new(connection) do |client|
            while input = client.gets
              puts ">>> FROM CLIENT: #{input}"
              message = JSON.parse(input)
              if message['command'] == 'get_threads'
                client.write({ result: [] }.to_json + "\n")
              end
            end
          end

          Thread.new(connection) do |client|
            client.write "HELLO\n"
          end
        end
      rescue => e
        puts ">>> ERROR: #{e}"
      end
    end
  end
end

class RemoteCommandProcessor < Byebug::Processor
  def initialize(server, interface = Byebug::LocalInterface.new)
    super(interface)
    @server = server
  end

  def at_line(context, file, line)
    process_commands(context, file, line)
  end

  def at_return(context, file, line)
    puts "return from #{line}"
  end

  def process_commands(context, file, line)
    context.step_into(1)
  end
end

def debug_start
  Byebug.handler = RemoteCommandProcessor.new(Server.new)
  Byebug.start
  Byebug.run_init_script(StringIO.new)
  Byebug.current_context.step_out(1, true)
end

debug_start
