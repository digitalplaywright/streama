module Streama
  
  class DefinitionDSL
    
    attr_reader :attributes
    
    def initialize(name)
      @attributes = {
        :name => name.to_sym,
        :actor => {}, 
        :act_object => {},
        :act_target => {},
        :act_object_group => {},
        :act_target_group => {},
        :options    => []

      }
    end

    def add_option(option)
      @attributes[:options] ||= []

      @attributes[:options] << option
    end

    def option(text)
      add_option( text )
    end
    
    delegate :[], :to => :@attributes
        
    def self.data_methods(*args)
      args.each do |method|
        define_method method do |*args|
          @attributes[method].store(args[0].is_a?(Symbol) ? args[0] : args[0].class.to_sym, args[1])
        end
      end
    end
    data_methods :actor, :act_object, :act_target, :act_object_group, :act_target_group

  end
  
end