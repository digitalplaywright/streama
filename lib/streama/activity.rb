module Streama
  module Activity
    extend ActiveSupport::Concern

    included do

      #include Mongoid::Document
      #include Mongoid::Timestamps

      field :verb,             :type => Symbol

      belongs_to :actor,      :polymorphic => true, :inverse_of => :activities,            :index => true
      belongs_to :act_object, :polymorphic => true, :inverse_of => :act_object_activities, :index => true
      belongs_to :act_target, :polymorphic => true, :inverse_of => :act_target_activities, :index => true

      has_and_belongs_to_many :grouped_actors, :class_name => "Space", :inverse_of => nil, :validate => false
      has_and_belongs_to_many :receivers,      :class_name => "Space", :inverse_of => nil, :validate => false

      embeds_many :options, :class_name => "StreamaOption", :as => :streama_optionable


      index({ :verb => 1 })
      index({ :name => 1 })

      validates_presence_of :actor_id, :actor_type, :verb

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
      # @return [Streama::Activity2] An Activity instance with data
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


    def refresh_data
      save(:validate => false)
    end

    protected

    def assign_properties(data = {})

      self.verb      = data.delete(:verb)

      cur_receivers  = data.delete(:receivers)

      if cur_receivers
        if cur_receivers.respond_to?(:each)
          cur_receivers.each do |sp|
            raise "receivers need to be of Space type. Got:" + sp.class.name unless sp.kind_of?(Space)
            self.receivers << sp
          end
        else
          #if only one receivers is supplied
          raise "receivers need to be of Space type. Got:" + cur_receivers.class.name unless cur_receivers.kind_of?(Space)

          self.receivers << cur_receivers
        end
      end

      [:actor, :act_object, :act_target].each do |type|

        cur_object = data[type]

        unless cur_object
          if definition.send(type.to_sym)
            raise verb.to_json
            #raise Streama::InvalidData.new(type)
          else
            next

          end
        end

        class_sym = cur_object.class.name.to_sym

        raise Streama::InvalidData.new(class_sym) unless definition.send(type) == class_sym

        case type
          when :actor
            self.actor = cur_object
          when :act_object
            self.act_object = cur_object
          when :act_target
            self.act_target = cur_object
          else
            raise "unknown type"
        end

        data.delete(type)

      end

      [:grouped_actor].each do |group|


        grp_object = data[group]

        if grp_object == nil
          if definition.send(group.to_sym)
            raise verb.to_json
            #raise Streama::InvalidData.new(group)
          else
            next

          end
        end

        grp_object.each do |cur_obj|
          raise Streama::InvalidData.new(class_sym) unless definition.send(group) == cur_obj.class.name.to_sym

          self.grouped_actors << cur_obj

        end

        data.delete(group)

      end

      def_options = definition.send(:options)
      def_options.each do |cur_option|
        cur_object = data[cur_option]

        if cur_object
          options << StreamaOption.new(:name => cur_option, :value => cur_object)
          data.delete(cur_option)

        else
          #all options defined must be used
          raise Streama::InvalidData.new(cur_object[0])
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
