require 'cod'
require 'msgpack'
require 'thread'

class RpcServer
  def initialize(host, port, handler)
    @channel = Cod.tcp_server("#{host}:#{port}")
    @handler = handler
  end

  def listen
    loop do
      begin
        puts 'wait for client'
        request, client = @channel.get_ext
        puts 'got client'
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN => e
        retry
      end

      begin
        obj = MessagePack.unpack(request)

        method = obj['method'].to_sym
        opts = Hash[obj['params'].map { |k, v| [k.to_sym, v] }]

        puts "---> #{method}"

        if opts.empty?
          response = @handler.send(method)
        else
          response = @handler.send(method, opts)
        end

        client.put MessagePack.pack(response)

        puts "<--- #{method}"
      rescue => e
        puts ">>> ERROR: #{e}"
        puts ">>> #{e.backtrace}"
      end
    end
  end
end

class RpcClient
  def initialize(host, port)
    @channel = Cod.tcp("#{host}:#{port}")

    # TODO: Cod is not thread-safe, so we need a mutex.
    # Find a more performant solution to making these
    # RPC calls thread-safe.
    @mutex = Mutex.new
  end

  def method_missing(sym, *args, &block)
    obj = {
      method: sym.to_s,
      params: args.first || {}
    }

    @mutex.synchronize {
      result = @channel.interact(MessagePack.pack(obj))
      return MessagePack.unpack(result)
    }
  end
end
