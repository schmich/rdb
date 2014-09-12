require 'sinatra'
require 'sinatra/json'
require 'rpc'
require 'json'

# TODO: Parameter validation on all calls.

client = RpcClient.new('localhost', 4444)

get '/' do
  erb :index
end

get '/running' do
  json({ running: client.running? })
end

get '/threads' do
  threads = client.get_threads
  threads.each do |thread|
    thread['backtrace'].each do |frame|
      frame['file'] = File.basename(frame['path'])
      frame['path'] = frame['path'].gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    end
  end
  json threads
end

get '/process' do
  json({ process: client.process })
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
  json({ running: running })
end

put '/resume' do
  running = client.resume
  json({ running: running })
end

put '/step-in' do
  client.step_in
  json({ result: true })
end

put '/step-over' do
  client.step_over
  json({ result: true })
end

put '/step-out' do
  client.step_out
  json({ result: true })
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
  json({ id: id })
end

delete '/breakpoints/:id' do
  id = params[:id].to_i
  result = client.remove_breakpoint(id: id)
  json({ success: result })
end
