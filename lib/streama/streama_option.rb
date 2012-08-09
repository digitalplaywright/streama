class StreamaOption
  include Mongoid::Document

  field :name,  :type => Symbol
  field :value, :type => String

  field :_id, :type => Symbol, default: ->{ name }

  embedded_in :streama_optionable, :polymorphic => true

end

