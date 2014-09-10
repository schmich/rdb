require 'byebug'
require 'rpc'
require 'thread'

class CommandHandler
  def initialize(debug_thread_group)
    @debug_thread_group = debug_thread_group

    @access = Mutex.new

    @waiting = false
    @mutex = Mutex.new
    @resource = ConditionVariable.new

    @command_queue = []
  end

  def get_threads
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
          path = context.frame_file(i)
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

  def eval(expr: nil)
    @access.synchronize {
      while !@waiting
      end

      context = Byebug.thread_context(Thread.main)
      begin
        return { success: context.frame_binding.eval(expr).inspect }
      rescue => e
        return { failure: e.inspect }
      end
    }
  end

  def pause
    @access.synchronize {
      context = Byebug.thread_context(Thread.main)
      context.interrupt

      @running = false
      @running
    }
  end

  def resume
    @access.synchronize {
      @command_queue << proc { |context|
        true
      }

      @mutex.synchronize {
        @resource.signal
      }

      @running = true
      @running
    }
  end

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
      puts '> wait'
      puts '> threads:'
      Thread.list.each do |thread|
        puts ">>> #{thread}: " + thread.status.to_s + ((thread == Thread.current) ? ' (current)' : '') + (thread == Thread.main ? ' (main)' : '')
      end

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

  def running?
    @access.synchronize {
      @running
    }
  end

  private

  def ignored?(thread)
    thread.group == @debug_thread_group
  end
end

class RemoteCommandProcessor < Byebug::Processor
  def initialize(interface = Byebug::LocalInterface.new)
    super(interface)

    debug_group = ThreadGroup.new
    @handler = CommandHandler.new(debug_group)
    @server = RpcServer.new('localhost', 4444, @handler)
    thread = Byebug::DebugThread.new do
      @server.listen
    end
    
    debug_group.add(thread)
    debug_group.enclose
  end
  
  def at_breakpoint(context, breakpoint)
    puts '> at breakpoint'
  end

  def at_catchpoint(context, excpt)
    puts '> at_catchpoint'
  end

  def at_tracing(context, file, line)
    puts '> at_tracing'
  end

  def at_line(context, file, line)
    puts "> at_line: #{file}:#{line}, reason: #{context.stop_reason}"
    process_commands(context, file, line)
  end

  def at_return(context, file, line)
    puts '> at_return'
    process_commands(context, file, line)
  end

  def process_commands(context, file, line)
    puts "> process_commands @ #{file}:#{line} in #{Thread.current}"
    loop do
      command = @handler.next_command
      break if command.call(context)
    end
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
