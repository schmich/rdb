module Kernel
  def rdb
    Byebug.handler = RemoteCommandProcessor.new
    Byebug.start
    Byebug.run_init_script(StringIO.new)
    Byebug.current_context.step_out(1, true)
  end

  alias_method :debugger, :rdb
end
