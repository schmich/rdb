require 'cod'
require 'msgpack'
require 'thread'
require 'set'

module Messaging
end

class Messaging::Server
  def initialize
    @clients = []
    @clients_lock = Mutex.new
  end

  def listen(host, port)
    channel = Cod.tcp_server("#{host}:#{port}")

    loop do
      begin
        payload, client = channel.get_ext
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ECONNRESET => e
        next
      end

      begin
        message = Messaging::Message.unpack(payload)
        @clients_lock.synchronize {
          @clients << client
        }
        handle_message(client, message)
      rescue => e
        puts ">>> Error: #{e}\n#{e.backtrace}"
      end
    end
  end

  def broadcast(message, params)
    payload = Messaging::Message.broadcast(message, params)
    @clients_lock.synchronize {
      @clients.reject! { |client|
        begin
          client.put(payload)
          false
        rescue IOError
          true
        end
      }
    }
  end

  private

  def handle_message(client, message)
    id = message[:id]
    command = message[:command]
    params = message[:params]

    result = if params.empty?
      self.send(command)
    else
      self.send(command, params)
    end

    client.put(Messaging::Message.result(id, result))
  end
end

class Messaging::Client
  def initialize
    @connected = false
    @connected_mon = Monitor.new
    @connected_wait = @connected_mon.new_cond

    @result_id = 0
    @result = {}
    @result_mon = {}
    @result_wait = {}
  end

  def connect_listen(host, port)
    @channel = Cod.tcp("#{host}:#{port}")

    set_connected

    loop do
      process_message
    end
  end

  def method_missing(symbol, *args, &block)
    message(symbol, args.first || {})
  end

  private

  def message(command, params)
    wait_connected

    id = @result_id += 1
    mon = @result_mon[id] ||= Monitor.new
    wait = @result_wait[id] ||= mon.new_cond

    payload = Messaging::Message.command(id, command, params)
    @channel.put(payload)

    mon.synchronize {
      wait.wait
    }

    result = @result[id]
    @result.delete(id)
    @result_mon.delete(id)
    @result_wait.delete(id)

    return result
  end

  def wait_connected
    if !@connected
      @connected_mon.synchronize do
        @connected_wait.wait_while { !@connected }
      end
    end
  end

  def set_connected
    @connected = true
    @connected_mon.synchronize {
      @connected_wait.signal
    }
  end

  def process_message
    begin
      payload = @channel.get
      obj = Messaging::Message.unpack(payload)

      case obj[:type]
      when :result
        handle_result(obj)
      when :broadcast
        handle_broadcast(obj)
      end
    rescue => e
      puts ">>> Error: #{e}\n#{e.backtrace}"
    end
  end

  def handle_result(message)
    id = message[:id]
    @result[id] = message[:result]
    @result_mon[id].synchronize {
      @result_wait[id].signal
    }
  end

  def handle_broadcast(message)
    method = message[:message]
    params = message[:params]
    self.send(method, params)
  end
end

class Messaging::Message
  def self.command(id, command, params)
    obj = {
      type: :command,
      id: id,
      command: command,
      params: params
    }

    MessagePack.pack(obj)
  end

  def self.result(id, result)
    obj = {
      type: :result,
      id: id,
      result: result
    }

    MessagePack.pack(obj)
  end

  def self.broadcast(message, params)
    obj = {
      type: :broadcast,
      message: message,
      params: params
    }

    MessagePack.pack(obj)
  end

  def self.unpack(payload)
    obj = MessagePack.unpack(payload)
    type = obj['type'].to_sym

    id = obj['id']

    params = nil
    if obj['params']
      params = Hash[obj['params'].map { |k, v| [k.to_sym, v] }]
    end

    case type
    when :broadcast
      { type: type, message: obj['message'].to_sym, params: params }
    when :result
      { type: type, id: id, result: obj['result'] }
    when :command
      { type: type, id: id, command: obj['command'].to_sym, params: params }
    end
  end
end
