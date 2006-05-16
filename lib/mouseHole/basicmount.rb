module MouseHole
class BasicMount
    def debug(msg); @logger.debug(msg) end
    def error(msg); @logger.error(msg) end
    def fatal(msg); @logger.fatal(msg) end
    def info(msg);  @logger.info(msg)  end
    def warn(msg);  @logger.warn(msg)  end
end
end
