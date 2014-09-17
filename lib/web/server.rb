require 'sinatra'
require 'sinatra/json'
require 'sinatra/sse'
require 'messaging'
require 'json'
require 'thin'

include Sinatra::SSE

set :bind, '0.0.0.0'
set :server, 'thin'

class CommandClient < Messaging::Client
  def initialize(event_clients)
    super()
    @event_clients = event_clients
  end

  def breakpoint
    for client in @event_clients
      data = JSON.dump(event: 'breakpoint-hit')
      client.push(:data => data)
    end
  end

  def breakpoint_created
    for client in @event_clients
      data = JSON.dump(event: 'breakpoint-created')
      client.push(:data => data)
    end
  end

  def breakpoint_deleted
    for client in @event_clients
      data = JSON.dump(event: 'breakpoint-deleted')
      client.push(:data => data)
    end
  end

  def step
    for client in @event_clients
      data = JSON.dump(event: 'step-hit')
      client.push(:data => data)
    end
  end
end

event_clients = []
client = CommandClient.new(event_clients)
Thread.new do
  client.connect_listen('localhost', 4444)
end

# TODO: Parameter validation on all calls.

get '/' do
  erb :index
end

get '/running' do
  json(running: client.running?)
end

get '/threads' do
  threads = client.threads
  threads.each do |thread|
    thread['backtrace'].each do |frame|
      frame['file'] = File.basename(frame['path'])
      frame['path'] = frame['path'].gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    end
  end
  json threads
end

get '/process' do
  json(process: client.process)
end

get '/source' do
  path = params[:path]
  # TODO: Seems insecure, any way to fix this?
  File.read(path)
end

# TODO: Make this secure in remote situations.
# Remote callers can request any file.
# TODO: Lots of security checks needed here to
# prevent arbitrary execution.
post '/open' do
  params = JSON.parse(request.body.read)
  path = params['path']
  line = params['line']

  # TODO: Do not hardcode editor.
  if line.nil?
   command = "gvim \"#{path}\""
  else
   command = "gvim \"#{path}\" +\"#{line}\""
  end

  system(command)
end

put '/pause' do
  running = client.pause
  json(running: running)
end

put '/resume' do
  running = client.resume
  json(running: running)
end

# TODO: Ensure step actually happened.
put '/step-in' do
  client.step_in
  json(success: true)
end

put '/step-over' do
  client.step_over
  json(success: true)
end

put '/step-out' do
  client.step_out
  json(success: true)
end

put '/eval' do
  params = JSON.parse(request.body.read)
  expr = params['expr']
  frame = params['frame']
  json client.eval(expr: expr, frame: frame.to_i)
end

get '/locals' do
  json client.locals
end

get '/breakpoints' do
  json client.breakpoints
end

post '/breakpoints' do
  params = JSON.parse(request.body.read)
  file = params['file']
  line = params['line']
  id = client.add_breakpoint(file: file, line: line)
  client.breakpoint_created
  json(id: id)
end

delete '/breakpoints/:id' do
  id = params[:id].to_i
  result = client.remove_breakpoint(id: id)
  client.breakpoint_deleted
  json(success: result)
end

get '/events' do
  sse_stream do |out|
    event_clients << out
  end
end
