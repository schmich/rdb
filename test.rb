=begin
t1 = Thread.new do
  loop do
    puts 'Thread 1'
    sleep 1
  end
end

t2 = Thread.new do
  loop do
    puts 'Thread 2'
    sleep 5
  end
end

t1.join
t2.join
=end

def foo(x)
  x * 3
end

x = 10
loop do
  x += foo(x)
  puts x
  sleep 1
end
