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

class Person
  def initialize(name)
    @name = name
  end

  attr_reader :name
end

def foo(x)
  x * 3
end

x = 10
loop do
  p = Person.new('Foo')
  puts p.name
  x += foo(x)
  puts x
  sleep 1
end
