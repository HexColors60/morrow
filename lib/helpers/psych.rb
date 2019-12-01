# Monkey patches for the Psych parser
module Helpers::Psych
  module ClassPrependMethods
    def load(*args)
      begin
        (@loading[Thread.current] ||= []) << args.last[:filename]
        super(*args)
      ensure
        @loading[Thread.current].pop
      end
    end
  end
  Psych.instance_variable_set(:@loading, {})
  Psych.singleton_class.prepend(ClassPrependMethods)

  module ClassMethods
    # return the filename of the file currently being loaded by load_file
    def current_filename
      @loading[Thread.current].last
    end
  end
  Psych.extend(ClassMethods)
end
