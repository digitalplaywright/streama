module Streama
  module Activity
    extend ActiveSupport::Concern

    included do

      #include Mongoid::Document
      #include Mongoid::Timestamps

      field :verb,             :type => Symbol


      field :actor_id,        :type => String
      field :actor_type,      :type => String
      field :act_object_id,   :type => String
      field :act_object_type, :type => String
      field :act_target_id,   :type => String
      field :act_target_type, :type => String

      field :act_object_group_ids,  :type => Array
      field :act_object_group_type, :type => String

      field :act_target_group_ids,  :type => Array
      field :act_target_group_type, :type => String

      embeds_many :options, :class_name => "StreamaOption", as: :streama_optionable

      field :receiver_ids,    :type => Array
      field :receiver_type,   :type => String

      index :name
      index [['actor_id', Mongo::ASCENDING], ['actor_type', Mongo::ASCENDING]]
      index [['act_object_id', Mongo::ASCENDING], ['act_object_type', Mongo::ASCENDING]]
      index [['act_target_id', Mongo::ASCENDING], ['act_target_type', Mongo::ASCENDING]]
      index [['act_object_group_ids', Mongo::ASCENDING], ['act_object_group_type', Mongo::ASCENDING]]
      index [['act_target_group_ids', Mongo::ASCENDING], ['act_target_group_type', Mongo::ASCENDING]]


      index [['receiver_ids', Mongo::ASCENDING], ['receiver_type', Mongo::ASCENDING]]

      validates_presence_of :actor, :verb

    end

    module ClassMethods

      # Defines a new Activity2 type and registers a definition
      #
      # @param [ String ] name The name of the activity
      #
      # @example Define a new activity
      #   activity(:enquiry) do
      #     actor :user, :cache => [:full_name]
      #     act_object :enquiry, :cache => [:subject]
      #     act_target :listing, :cache => [:title]
      #   end
      #
      # @return [Definition] Returns the registered definition
      def activity(name, &block)
        definition = Streama::DefinitionDSL.new(name)
        definition.instance_eval(&block)
        Streama::Definition.register(definition)
      end

      # Publishes an activity using an activity name and data
      #
      # @param [ String ] verb The verb of the activity
      # @param [ Hash ] data The data to initialize the activity with.
      #
      # @return [Streama::Activity] An Activity instance with data
      def publish(verb, data)
        new.publish({:verb => verb}.merge(data))
      end

    end



    # Publishes the activity to the receivers
    #
    # @param [ Hash ] options The options to publish with.
    #
    def publish(data = {})
      assign_properties(data)

      self.save
      self
    end

    # Returns an instance of an actor, act_object or act_target
    #
    # @param [ Symbol ] type The data type (actor, act_object, act_target) to return an instance for.
    #
    # @return [Mongoid::Document] document A mongoid document instance
    def load_instance(type)
      data_type = self.send(type.to_s+'_type')
      data_id   = self.send(type.to_s+'_id')

      if data_id.present?
        data_type.constantize.find(data_id)
      else
        nil
      end
    end

    def refresh_data
      save(:validate => false)
    end

    protected

    def assign_properties(data = {})

      self.verb      = data.delete(:verb)

      cur_receivers  = data.delete(:receivers)

      if cur_receivers
        self.receiver_ids = []
        cur_receivers.each do |receiver|
          self.receiver_ids << receiver.id
        end

        self.receiver_type = cur_receivers.first.class.to_s
      end

      [:actor, :act_object, :act_target].each do |type|

        act_object = arguments[type]

        if act_object == nil
          if definition.send(type.to_sym) != nil
            raise verb.to_json
            raise Streama::InvalidData.new(type)
          else
            next
          end
        end

        class_sym = act_object.class.name.to_sym

        raise Streama::InvalidData.new(class_sym) unless definition.send(type) == class_sym

        write_attribute(type.to_s+"_id",   act_object.id.to_s)
        write_attribute(type.to_s+"_type", act_object.class.name)

        arguments.delete(type)

      end

      [:act_object_group, :act_target_group].each do |group|

        cur_array = []

        grp_object = data[group]

        if grp_object == nil
          if definition.send(group.to_sym).empty?
            next

          else
            raise verb.to_json
            raise Streama::InvalidData.new(group)
          end
        end

        grp_object.each do |cur_obj|

          class_sym = cur_object.class.name.to_sym

          raise Streama::InvalidData.new(class_sym) unless definition.send(group).has_key?(class_sym)

          cur_array << cur_obj.id


        end


        write_attribute(group.to_s+"_ids",  cur_array)
        write_attribute(group.to_s+"_type", grp_object.first.class.name)

        data.delete(group)

      end

      def_options = definition.send(:options)
      def_options.each do |cur_option|
        act_object = data[cur_option]

        if act_object
          options << StreamaOption.new(name: cur_option, value: act_object)
          data.delete(cur_option)

        else
          #all options defined must be used
          raise Streama::InvalidData.new(act_object[0])
        end
      end

      if data.size > 0
        raise "unexpected arguments: " + data.to_json
      end

    end

    def definition
      @definition ||= Streama::Definition.find(verb)
    end


  end
end
