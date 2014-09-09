x = 42

def foo x
  x * 2
end

loop do
  puts "x = #{x}"
  x += foo(x)
  sleep 1
end
