require 'socket'
require 'json'

socket = TCPSocket.new('localhost', 1234)
while line = socket.gets
  puts line
  socket.write({ command: 'get_threads' }.to_json + "\n")
  resp = socket.gets
  puts resp
end
socket.close
