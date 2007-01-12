module MouseHole
  module LoggerMixin
    [:debug, :info, :warn, :error].each do |m|
      define_method(m) do |txt, *opts|
        opts = opts.first || {}
        if opts[:since]
          txt = "%s (%0.4f)" % [txt, Time.now.to_f - opts[:since].to_f]
        end
        MouseHole::CENTRAL.logger.send m, txt
      end
    end
  end
end
