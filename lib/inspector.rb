require 'set'

class Inspector
  def initialize
    @seen_ids = Set.new
  end

  def self.inspect(obj)
    Inspector.new.inspect(obj)
  end

  def inspect(obj)
    if !@seen_ids.add?(obj.object_id)
      return "(circular reference)"
    end

    # Range, Regex, Block, Proc, lambda, Thread, Set, ...
    case obj
    when Fixnum, Float, TrueClass, FalseClass, NilClass, String, Class, Symbol
      return { class: obj.class.name, inspect: obj }
    when Array
      return { class: obj.class.name, inspect: obj.map { |x| inspect(x) } }
    when Hash
      inspected = []
      obj.each do |k, v|
        inspected << [inspect(k), inspect(v)]
      end
      return { class: obj.class.name, inspect: inspected }
    end

    vars = Hash[obj.instance_variables.map { |var|
      [var, inspect(obj.instance_variable_get(var))]
    }]

    return {
      class: obj.class.name,
      inspect: vars
    }
  end
end
