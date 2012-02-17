module Streama
  module Activity
    extend ActiveSupport::Concern
    
    included do
      
      #include Mongoid::Document
      #include Mongoid::Timestamps
    
      field :verb,         :type => Symbol
      field :actor,        :type => Hash
      field :object,       :type => Hash
      field :object_group, :type => Array
      field :act_target_group, :type => Array
      field :options,      :type => Hash


      field :act_target,       :type => Hash
      field :receivers,    :type => Array
          
      index :name
      index [['actor._id', Mongo::ASCENDING], ['actor._type', Mongo::ASCENDING]]
      index [['object._id', Mongo::ASCENDING], ['object._type', Mongo::ASCENDING]]
      index [['act_target._id', Mongo::ASCENDING], ['act_target._type', Mongo::ASCENDING]]
      index [['object_group.id', Mongo::ASCENDING], ['object_group.type', Mongo::ASCENDING]]
      index [['act_target_group.id', Mongo::ASCENDING], ['act_target_group.type', Mongo::ASCENDING]]


      index [['receivers.id', Mongo::ASCENDING], ['receivers.type', Mongo::ASCENDING]]
          
      validates_presence_of :actor, :verb
      before_save :assign_data
      
    end
    
    module ClassMethods

      # Defines a new Activity2 type and registers a definition
      #
      # @param [ String ] name The name of the activity
      #
      # @example Define a new activity
      #   activity(:enquiry) do
      #     actor :user, :cache => [:full_name]
      #     object :enquiry, :cache => [:subject]
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
        receivers = data.delete(:receivers)
        options   = data.delete(:options)
        new({:verb => verb}.merge(data)).publish(:receivers => receivers, :options => options)
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
    def publish(options = {})
      actor = load_instance(:actor)
      self.receivers = (options[:receivers] || actor.followers).map { |r| { :id => r.id, :type => r.class.to_s } }
      self.options   = options[:options] if options[:options] != nil
      self.save
      self
    end

    # Returns an instance of an actor, object or act_target
    #
    # @param [ Symbol ] type The data type (actor, object, act_target) to return an instance for.
    #
    # @return [Mongoid::Document] document A mongoid document instance
    def load_instance(type)
      (data = self.send(type)).is_a?(Hash) ? data['type'].to_s.camelcase.constantize.find(data['id']) : data
    end

    def refresh_data
      assign_data
      save(:validate => false)
    end

    protected

    def assign_data

      [:actor, :object, :act_target].each do |type|
        next unless object = load_instance(type)

        class_sym = object.class.name.underscore.to_sym

        raise Streama::InvalidData.new(class_sym) unless definition.send(type).has_key?(class_sym)

        hash = {'id' => object.id, 'type' => object.class.name}

        if fields = definition.send(type)[class_sym].try(:[],:cache)
          fields.each do |field|
            raise Streama::InvalidField.new(field) unless object.respond_to?(field)
            hash[field.to_s] = object.send(field)
          end
        end
        write_attribute(type, hash)
      end

      [:object_group, :act_target_group].each do |group|

        cur_array = []


        grp_object =  self.send(group)

        next unless grp_object

        grp_object.each do |cur_obj|

          next unless object = cur_obj.is_a?(Hash) ? cur_obj['type'].to_s.camelcase.constantize.find(cur_obj['id']) : cur_obj


          class_sym = object.class.name.underscore.to_sym

          raise Streama::InvalidData.new(class_sym) unless definition.send(group).has_key?(class_sym)


          hash = {'id' => object.id, 'type' => object.class.name}

          if fields = definition.send(group)[class_sym][:cache]
            fields.each do |field|
              raise Streama::InvalidField.new(field) unless object.respond_to?(field)
              hash[field.to_s] = object.send(field)
            end
          end
          cur_array << hash


        end

        write_attribute(group, cur_array)


      end

    end

    def definition
      @definition ||= Streama::Definition.find(verb)
    end


  end
end
