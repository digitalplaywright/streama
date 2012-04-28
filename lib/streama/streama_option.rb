class StreamaOption
  include Mongoid::Document

  field :name,  :type => String
  field :value, :type => String

  embedded_in :streama_optionable, polymorphic: true

end

