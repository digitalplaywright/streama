module Streama
  module Activity
    extend ActiveSupport::Concern
    
    included do
      
      #include Mongoid::Document
      #include Mongoid::Timestamps
    
      field :verb,             :type => Symbol
      field :actor,            :type => Hash
      field :act_object,       :type => Hash
      field :act_target,       :type => Hash

      field :act_object_group, :type => Array
      field :act_target_group, :type => Array

      field :options,          :type => Hash


      field :receivers,    :type => Array
          
      index :name
      index [['actor._id', Mongo::ASCENDING], ['actor._type', Mongo::ASCENDING]]
      index [['act_object._id', Mongo::ASCENDING], ['act_object._type', Mongo::ASCENDING]]
      index [['act_target._id', Mongo::ASCENDING], ['act_target._type', Mongo::ASCENDING]]
      index [['act_object_group.id', Mongo::ASCENDING], ['act_object_group.type', Mongo::ASCENDING]]
      index [['act_target_group.id', Mongo::ASCENDING], ['act_target_group.type', Mongo::ASCENDING]]


      index [['receivers.id', Mongo::ASCENDING], ['receivers.type', Mongo::ASCENDING]]
          
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
      
      def stream_for(actor, options={})
        query = {:receivers => {'$elemMatch' => {:id => actor.id, :type => actor.class.to_s}}}
        query.merge!({:verb => options[:type]}) if options[:type]
        self.where(query).without(:receivers).desc(:created_at)
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
      (data = self.send(type)).is_a?(Hash) ? data['type'].to_s.camelcase.constantize.find(data['id']) : data
    end

    def refresh_data
      save(:validate => false)
    end

    protected

    def assign_properties(data = {})

      self.verb      = data.delete(:verb)

      cur_receivers  = data.delete(:receivers)

      if cur_receivers == nil && data[:actor].respond_to?(:followers)
        data[:actor].followers
      end

      self.receivers = cur_receivers.map { |r| { :id => r.id, :type => r.class.to_s } }


      [:actor, :act_object, :act_target].each do |type|

        cur_object = data[type]

        if cur_object == nil
          if definition.send(type.to_sym) != nil
            raise verb.to_json
            raise Streama::InvalidData.new(type)
          else
            next
          end
        end

        class_sym = cur_object.class.name.to_sym

        raise Streama::InvalidData.new(class_sym) unless definition.send(type) == class_sym


        hash = {'id' => cur_object.id, 'type' => cur_object.class.name}

        if fields = definition.send(type)[class_sym].try(:[],:cache)
          fields.each do |field|
            raise Streama::InvalidField.new(field) unless cur_object.respond_to?(field)
            hash[field.to_s] = cur_object.send(field)
          end
        end

        write_attribute(type, hash)

        data.delete(type)

      end

      [:act_object_group, :act_target_group].each do |group|

        cur_array = []

        grp_object = data[type]

        if grp_object == nil
          if definition.send(group.to_sym) != nil
            raise verb.to_json
            raise Streama::InvalidData.new(group)
          else
            next
          end
        end

        grp_object.each do |cur_obj|

          class_sym = cur_obj.class.name.underscore.to_sym

          raise Streama::InvalidData.new(class_sym) unless definition.send(group).has_key?(class_sym)


          hash = {'id' => cur_obj.id, 'type' => cur_obj.class.name}

          if fields = definition.send(group)[class_sym][:cache]
            fields.each do |field|
              raise Streama::InvalidField.new(field) unless cur_obj.respond_to?(field)
              hash[field.to_s] = cur_obj.send(field)
            end
          end
          cur_array << hash


        end


        write_attribute(group, cur_array)

        data.delete(group)

      end

      def_options = definition.send(:options)
      def_options.each do |cur_option|
        act_object = data[cur_option]

        if act_object
          self.options[cur_option] = act_object
        else
          #all options defined must be used
          raise Streama::InvalidData.new(act_object[0])
        end
      end



    end

    def definition
      @definition ||= Streama::Definition.find(verb)
    end


  end
end
