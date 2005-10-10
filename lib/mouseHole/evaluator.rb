module MouseHole
# The Evaluator class is used during the script security check.  Metadata about the
# script is stored here.  Basically, we taint this object and run the code inside
# +evaluate+ at a $SAFE level of 4.  Exceptions rise.
class Evaluator
    attr_accessor :script_path, :script_id, :code, :obj
    def initialize( script_path, code )
        @script_path, @code = script_path, code
    end
    def evaluate
        if script_path =~ /\.user\.js$/
            @obj = StarmonkeyUserScript.new( code )
        else
            @obj = eval( code )
        end
    rescue Exception => e
        fake = Struct.new( :lineno, :message, :backtrace )
        ctx, lineno, func, message = "#{ e.backtrace[0] }:#{ e.message }".split( /\s*:\s*/, 4 )        
        message = "#{ e.class } on line #{ lineno }: `#{ message }'"
        @obj = fake.new( lineno, message, e.backtrace * "\n" )
    end
end
end
