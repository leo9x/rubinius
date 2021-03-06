class Exception
  attr_accessor :locations
  attr_accessor :cause
  attr_accessor :custom_backtrace

  def initialize(message = nil)
    @reason_message = message
    @locations = nil
    @backtrace = nil
    @custom_backtrace = nil
  end

  def capture_backtrace!(offset=1)
    @locations = Rubinius::VM.backtrace offset
  end

  def ==(other)
    other.instance_of?(__class__) &&
      message == other.message &&
      backtrace == other.backtrace
  end

  def to_s
    if @reason_message
      @reason_message.to_s
    else
      self.class.to_s
    end
  end

  # This is here rather than in yaml.rb because it contains "private"
  # information, ie, the list of ivars. Putting it over in the yaml
  # source means it's easy to forget about.
  def to_yaml_properties
    list = super
    list.delete :@backtrace
    list.delete :@custom_backtrace
    return list
  end

  def message
    @reason_message
  end

  # Needed to properly implement #exception, which must clone and call
  # #initialize again, BUT not a subclasses initialize.
  alias_method :__initialize__, :initialize

  def backtrace
    return @custom_backtrace if @custom_backtrace

    if backtrace?
      awesome_backtrace.to_mri
    else
      nil
    end
  end

  # Indicates if the Exception has a backtrace set
  def backtrace?
    (@backtrace || @locations) ? true : false
  end

  def awesome_backtrace
    @backtrace ||= Rubinius::Backtrace.backtrace(@locations)
  end

  def render(header="An exception occurred", io=STDERR, color=true)
    message_lines = message.to_s.split("\n")

    io.puts header
    io.puts
    io.puts "    #{message_lines.shift} (#{self.class})"

    message_lines.each do |line|
      io.puts "    #{line}"
    end

    if @custom_backtrace
      io.puts "\nUser defined backtrace:"
      io.puts
      @custom_backtrace.each do |line|
        io.puts "    #{line}"
      end
    end

    io.puts "\nBacktrace:"
    io.puts
    io.puts awesome_backtrace.show("\n", color)

    cause = @cause
    while cause
      io.puts "\nCaused by: #{cause.message} (#{cause.class})"

      if @custom_backtrace
        io.puts "\nUser defined backtrace:"
        io.puts
        @custom_backtrace.each do |line|
          io.puts "    #{line}"
        end
      end

      io.puts "\nBacktrace:"
      io.puts
      io.puts cause.awesome_backtrace.show

      cause = cause.cause
    end

  end

  def set_backtrace(bt)
    if bt.kind_of? Rubinius::Backtrace
      @backtrace = bt
    else
      # See if we stashed a Backtrace object away, and use it.
      if hidden_bt = Rubinius::Backtrace.detect_backtrace(bt)
        @backtrace = hidden_bt
      else
        type_error = TypeError.new "backtrace must be Array of String"
        case bt
        when Array
          if bt.all? { |s| s.kind_of? String }
            @custom_backtrace = bt
          else
            raise type_error
          end
        when String
          @custom_backtrace = [bt]
        when nil
          @custom_backtrace = nil
        else
          raise type_error
        end
      end
    end
  end

  # This is important, because I subclass can just override #to_s and calling
  # #message will call it. Using an alias doesn't achieve that.
  def message
    to_s
  end

  def inspect
    s = self.to_s
    if s.empty?
      self.class.name
    else
      "#<#{self.class.name}: #{s}>"
    end
  end

  class << self
    alias_method :exception, :new
  end

  def exception(message=nil)
    if message
      unless message.equal? self
        # As strange as this might seem, this IS actually the protocol
        # that MRI implements for this. The explicit call to
        # Exception#initialize (via __initialize__) is exactly what MRI
        # does.
        e = clone
        e.__initialize__(message)
        return e
      end
    end

    self
  end

  def location
    [context.file.to_s, context.line]
  end
end

class PrimitiveFailure < Exception
end

class ScriptError < Exception
end

class StandardError < Exception
end

class SignalException < Exception
end

class NoMemoryError < Exception
end

class ZeroDivisionError < StandardError
end

class ArgumentError < StandardError
  def to_s
    if @given and @expected
      if @method_name
        "method '#{@method_name}': given #{@given}, expected #{@expected}"
      else
        "given #{@given}, expected #{@expected}"
      end
    else
      super
    end
  end
end

class UncaughtThrowError < ArgumentError
end

class IndexError < StandardError
end

class StopIteration < IndexError
end

class RangeError < StandardError
end

class FloatDomainError < RangeError
end

class LocalJumpError < StandardError
end

class NameError < StandardError
  attr_reader :name

  def initialize(*args, receiver: nil)
    super(args.shift)

    @name = args.shift
    @receiver = receiver
  end

  def receiver
    if @receiver
      @receiver
    else
      raise ArgumentError, 'no receiver is available'
    end
  end
end

class NoMethodError < NameError
  attr_reader :name
  attr_reader :args

  def initialize(*arguments, **options)
    super(arguments.shift, **options)
    @name = arguments.shift
    @args = arguments.shift
  end
end

class RuntimeError < StandardError
end

class SecurityError < StandardError
end

class ThreadError < StandardError
end

class FiberError < StandardError
end

class TypeError < StandardError
end

class FloatDomainError < RangeError
end

class RegexpError < StandardError
end

class LoadError < ScriptError
  attr_accessor :path

  class InvalidExtensionError < LoadError
  end

  class MRIExtensionError < InvalidExtensionError
  end
end

class NotImplementedError < ScriptError
end

class Interrupt < SignalException
  def initialize(*args)
    super(args.shift)
    @name = args.shift
  end
end

class IOError < StandardError
end

class EOFError < IOError
end

class LocalJumpError < StandardError
end

class SyntaxError < ScriptError
  attr_accessor :column
  attr_accessor :line
  attr_accessor :file
  attr_accessor :code

  def self.from(message, column, line, code, file)
    exc = new message
    exc.file = file
    exc.line = line
    exc.column = column
    exc.code = code
    exc
  end

  def reason
    @reason_message
  end
end

class SystemExit < Exception

  ##
  # Process exit status if this exception is raised

  attr_reader :status

  ##
  # Creates a SystemExit exception with optional status and message.  If the
  # status is omitted, Process::EXIT_SUCCESS is used.
  #--
  # *args is used to simulate optional prepended argument like MRI

  def initialize(first=nil, *args)
    if first.kind_of?(Fixnum)
      status = first
      super(*args)
    else
      status = Process::EXIT_SUCCESS
      super
    end

    @status = status
  end

  ##
  # Returns true is exiting successfully, false if not. A successful exit is
  # one with a status equal to 0 (zero). Any other status is considered a
  # unsuccessful exit.

  def success?
    status == Process::EXIT_SUCCESS
  end

end


class SystemCallError < StandardError

  attr_reader :errno

  def self.errno_error(message, errno, location)
    Rubinius.primitive :exception_errno_error
    raise PrimitiveFailure, "SystemCallError.errno_error failed"
  end

  # We use .new here because when errno is set, we attempt to
  # lookup and return a subclass of SystemCallError, specificly,
  # one of the Errno subclasses.
  def self.new(*args)
    # This method is used 2 completely different ways. One is when it's called
    # on SystemCallError, in which case it tries to construct a Errno subclass
    # or makes a generic instead of itself.
    #
    # Otherwise it's called on a Errno subclass and just helps setup
    # a instance of the subclass
    if self.equal? SystemCallError
      case args.size
      when 1
        if args.first.kind_of?(Fixnum)
          errno = args.first
          message = nil
        else
          errno = nil
          message = StringValue(args.first)
        end
        location = nil
      when 2
        message, errno = args
        location = nil
      when 3
        message, errno, location = args
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 1..3)"
      end

      # If it corresponds to a known Errno class, create and return it now
      if errno && error = SystemCallError.errno_error(message, errno, location)
        return error
      else
        return super(message, errno, location)
      end
    else
      case args.size
      when 0
        message = nil
        location = nil
      when 1
        message = StringValue(args.first)
        location = nil
      when 2
        message, location = args
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 0..2)"
      end

      if defined?(self::Errno) && self::Errno.kind_of?(Fixnum)
        errno = self::Errno
        error = SystemCallError.errno_error(message, self::Errno, location)
        if error && error.class.equal?(self)
          return error
        end
      end

      error = allocate
      Rubinius::Unsafe.set_class error, self
      Rubinius.privately { error.initialize(*args) }
      return error
    end
  end

  # Must do this here because we have a unique new and otherwise .exception will
  # call Exception.new because of the alias in Exception.
  class << self
    alias_method :exception, :new
  end

  # Use splat args here so that arity returns -1 to match MRI.
  def initialize(*args)
    kls = self.class
    message, errno, location = args
    @errno = errno

    msg = "unknown error"
    msg << " @ #{StringValue(location)}" if location
    msg << " - #{StringValue(message)}" if message
    super(msg)
  end
end

class KeyError < IndexError
end

class SignalException < Exception

  attr_reader :signo
  attr_reader :signm

  def initialize(signo = nil, signm = nil)
    # MRI overrides this behavior just for SignalException itself
    # but not for anything that inherits from it, therefore we
    # need this ugly check to make sure it works as intented.
    return super(signo) unless self.class == SignalException
    if signo.is_a? Integer
      unless @signm = Signal::Numbers[signo]
        raise ArgumentError, "invalid signal number #{signo}"
      end
      @signo = signo
      @signm = signm || "SIG#{@signm}"
    elsif signo
      if signm
        raise ArgumentError, "wrong number of arguments (2 for 1)"
      end
      signm = signo
      if signo.kind_of?(Symbol)
        signm = signm.to_s
      else
        signm = StringValue(signm)
      end
      signm = signm[3..-1] if signm.prefix? "SIG"
      unless @signo = Signal::Names[signm]
        raise ArgumentError, "invalid signal name #{signm}"
      end
      @signm = "SIG#{signm}"
    end
    super(@signm)
  end
end

class StopIteration
  attr_accessor :result
  private :result=
end

##
# Base class for various exceptions raised in the VM.

class Rubinius::VMException < Exception
end

##
# Raised in the VM when an assertion fails.

class Rubinius::AssertionError < Rubinius::VMException
end

##
# Raised in the VM when attempting to read/write outside
# the bounds of an object.

class Rubinius::ObjectBoundsExceededError < Rubinius::VMException
end

# Defined by the VM itself
class Rubinius::InvalidBytecode < Rubinius::Internal
  attr_reader :compiled_code
  attr_reader :ip

  def message
    if @compiled_code
      if @ip and @ip >= 0
        "#{super} - at #{@compiled_code.name}+#{@ip}"
      else
        "#{super} - method #{@compiled_code.name}"
      end
    else
      super
    end
  end
end

class InterpreterError < Exception

end

class DeadlockError < Exception

end

# MRI has an Exception class named "fatal" that is raised
# by the rb_fatal function. The class is not accessible from
# ruby because the name is begins with a lower-case letter.
# Also, the exception cannot be rescued.
#
# To support rb_fatal in the C-API, Rubinius provides the
# following FatalError class. If it clashes with code in
# the wild, we can rename it.

class FatalError < Exception
end
