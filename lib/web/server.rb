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

put '/pause' do
  running = client.pause
  json({ running: running })
end

put '/resume' do
  running = client.resume
  json({ running: running })
end

put '/step_in' do
  client.step_in
  json({ result: true })
end

put '/step_over' do
  client.step_over
  json({ result: true })
end

put '/step_out' do
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
