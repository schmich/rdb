require 'byebug'
require 'messaging'
require 'inspector'
require 'thread'

class CommandServer < Messaging::Server
  def initialize()
    super()

    @debug_thread_group = nil

    @access = Mutex.new

    @waiting = false
    @mutex = Mutex.new
    @resource = ConditionVariable.new

    @command_queue = []
  end

  def start
    @debug_thread_group = group = ThreadGroup.new

    thread = Byebug::DebugThread.new do
      listen('0.0.0.0', 4444)
    end
    
    group.add(thread)
    group.enclose
  end

  remote!
  def threads
    @access.synchronize {
      # TODO: Better sync
      while !@waiting
      end

      threads = []
      Thread.list.each do |t|
        next if ignored? t
        
        backtrace = []

        context = Byebug.thread_context(t)
        stack_size = context.calced_stack_size

        (0...stack_size).each do |i|
          path = File.expand_path(context.frame_file(i))
          line = context.frame_line(i)
          klass = context.frame_class(i).to_s
          klass = nil if klass.empty?
          method = context.frame_method(i)

          backtrace << {
            path: path,
            line: line,
            class: klass,
            method: method,
          }
        end

        threads << {
          id: context.thnum,
          main: t == Thread.main,
          status: t.status,
          alive: t.alive?,
          priority: t.priority,
          safe_level: t.safe_level,
          backtrace: backtrace
        }
      end

      threads
    }
  end

  remote!
  def process
    @access.synchronize {
      {
        id: Process.pid,
        argv: ARGV,
        script: $0,
        env: ENV.to_h,
        config: RbConfig::CONFIG
      }
    }
  end

  remote!
  def locals
    @access.synchronize {
      while !@waiting
      end

      vars = {}
      context = Byebug.thread_context(Thread.main)
      syms = context.frame_binding.eval('local_variables')
      syms.each do |sym|
        name = sym.to_s
        vars[name] = context.frame_binding.eval(name).inspect
      end

      vars
    }
  end

  remote!
  def eval(expr: nil, frame: nil)
    @access.synchronize {
      while !@waiting
      end

      context = Byebug.thread_context(Thread.main)
      begin
        binding = context.frame_binding(frame)
        value = Inspector.inspect(binding.eval(expr))
        return { success: true, value: value }
      rescue Exception => e
        return { success: false, class: e.class.name, message: e.message }
      end
    }
  end

  remote!
  def breakpoints
    @access.synchronize {
      Byebug.breakpoints.map do |bp|
        {
          id: bp.id,
          line: bp.pos,
          path: bp.source
        }
      end
    }
  end

  remote!
  def add_breakpoint(file: nil, line: nil)
    @access.synchronize {
      breakpoint = Byebug::Breakpoint.add(file, line)
      broadcast(:breakpoint_created)
      breakpoint.id
    }
  end

  remote!
  def remove_breakpoint(id: nil)
    @access.synchronize {
      breakpoint = Byebug::Breakpoint.remove(id)
      broadcast(:breakpoint_deleted)
      true
    }
  end

  remote!
  def pause
    @access.synchronize {
      context = Byebug.thread_context(Thread.main)
      context.interrupt

      false
    }
  end

  remote!
  def resume
    @access.synchronize {
      @command_queue << proc { |context|
        true
      }

      @mutex.synchronize {
        @resource.signal
      }

      true
    }
  end

  remote!
  def step_in
    @access.synchronize {
      @command_queue << proc { |context|
        context.step_into(1)
        true
      }

      @mutex.synchronize {
        @resource.signal
      }

      true
    }
  end
  
  remote!
  def step_over
    @access.synchronize {
      @command_queue << proc { |context|
        context.step_over(1)
        true
      }

      @mutex.synchronize {
        @resource.signal
      }

      true
    }
  end

  remote!
  def step_out
    @access.synchronize {
      @command_queue << proc { |context|
        context.step_out(1)
        true
      }

      @mutex.synchronize {
        @resource.signal
      }

      true
    }
  end

  def next_command
    if @command_queue.empty?
      @mutex.synchronize {
        @waiting = true
        # TODO: Fix this synchronization. Using a condition variable here
        # triggers Ruby's deadlock detection, so for now, we use a limited
        # sleep with repeated checking.
        while @command_queue.empty?
          sleep 0.1
        end
        @waiting = false
      }
    end

    return @command_queue.shift
  end

  remote!
  def running?
    @access.synchronize {
      @running
    }
  end

  def running=(running)
    @running = running
  end

  private

  def ignored?(thread)
    thread.group == @debug_thread_group
  end
end

class RemoteCommandProcessor < Byebug::Processor
  def initialize(interface = Byebug::LocalInterface.new)
    super(interface)

    @server = CommandServer.new
    @server.start
  end
  
  def at_breakpoint(context, breakpoint)
    puts '> at_breakpoint'
  end

  def at_catchpoint(context, excpt)
    puts '> at_catchpoint'
  end

  def at_tracing(context, file, line)
    puts '> at_tracing'
  end

  def at_line(context, file, line)
    puts "> at_line: #{file}:#{line}, reason: #{context.stop_reason}"
    @server.broadcast(:break)
    process_commands(context, file, line)
  end

  def at_return(context, file, line)
    puts '> at_return'
    process_commands(context, file, line)
  end

  def process_commands(context, file, line)
    puts "> process_commands @ #{file}:#{line} in #{Thread.current}"
    @server.running = false
    loop do
      command = @server.next_command
      break if command.call(context)
    end
    @server.running = true
  end
end

def debug_start
  Byebug.handler = RemoteCommandProcessor.new
  Byebug.start
  Byebug.run_init_script(StringIO.new)
  # TODO: Why 2? 
  Byebug.current_context.step_out(2, true)
end

debug_start
