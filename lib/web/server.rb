require 'sinatra'
require 'sinatra/json'
require 'sinatra/sse'
require 'messaging'
require 'json'
require 'thin'

include Sinatra::SSE

set :bind, '0.0.0.0'
set :server, 'thin'

class EventManager
  def initialize
    @clients = []
  end

  def broadcast(attrs)
    data = JSON.dump(attrs)
    for client in @clients
      client.push(:data => data)
    end
  end

  attr_reader :clients
end

class CommandTarget < Messaging::Client
  def initialize(event_manager)
    super()
    @events = event_manager
  end

  remote!
  def break
    @events.broadcast(event: 'break')
  end

  remote!
  def breakpoint_created
    @events.broadcast(event: 'breakpoint-created')
  end

  remote!
  def breakpoint_deleted
    @events.broadcast(event: 'breakpoint-deleted')
  end
end

events = EventManager.new
target = CommandTarget.new(events)
Thread.new do
  target.connect_listen('localhost', 4444)
end

# TODO: Parameter validation on all calls.

get '/' do
  erb :index
end

get '/running' do
  json(running: target.running?)
end

get '/threads' do
  threads = target.threads
  threads.each do |thread|
    thread['backtrace'].each do |frame|
      frame['file'] = File.basename(frame['path'])
      frame['path'] = frame['path'].gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    end
  end
  json threads
end

get '/process' do
  json(process: target.process)
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
  running = target.pause
  json(running: running)
end

put '/resume' do
  running = target.resume
  json(running: running)
end

# TODO: Ensure step actually happened.
put '/step-in' do
  target.step_in
  json(success: true)
end

put '/step-over' do
  target.step_over
  json(success: true)
end

put '/step-out' do
  target.step_out
  json(success: true)
end

put '/eval' do
  params = JSON.parse(request.body.read)
  expr = params['expr']
  frame = params['frame']
  json target.eval(expr: expr, frame: frame.to_i)
end

get '/locals' do
  json target.locals
end

get '/breakpoints' do
  json target.breakpoints
end

post '/breakpoints' do
  params = JSON.parse(request.body.read)
  file = params['file']
  line = params['line']
  id = target.add_breakpoint(file: file, line: line)
  json(id: id)
end

delete '/breakpoints/:id' do
  id = params[:id].to_i
  result = target.remove_breakpoint(id: id)
  json(success: result)
end

get '/events' do
  sse_stream do |out|
    events.clients << out
  end
end
