module Remotely
  module Associations
    # A set class methods for defining associations that are retreived from
    # a remote API. They're available to all classes which inherit from
    # ActiveRecord::Base orRemotely::Model.
    #
    #  class Show < ActiveRecord::Base
    #    has_many_remote   :members
    #    has_one_remote    :set
    #    belongs_to_remote :station
    #  end
    #
    # = Warning
    #
    # Just like with ActiveRecord, associations will overwrite any instance method
    # with the same name as the association. So don't do that.
    #
    # = Cardinality and Defining Associations
    #
    # Remotely can be used to specify one-to-one and one-to-many associations.
    # Many-to-many is not supported.
    #
    # Unlike ActiveRecord, remote associations are only defined on the client side.
    # +has_many+ relations have no accompanying +belongs_to+.
    #
    # == One-to-many
    #
    # Use +has_many_remote+ to define a one-to-many relationship where the model
    # you are defining it in is the parent.
    #
    # === URI Assumptions
    #
    # Remotely assumes all +has_many_remote+ associations can be found at:
    #
    #  /model_name(plural)/id/association_name(plural)
    #
    # ==== Example
    #
    #  class User < ActiveRecord::Base
    #    has_many_remote :friends
    #  end
    #
    #  user = User.new(:id => 1)
    #  user.friends # => /users/1/friends
    #
    #
    # == One-to-one
    #
    # Use +has_one_remote+ to define a one-to-one relationship.
    #
    # === URI Assumptions
    #
    # Remotely assumes all +has_one_remote+ associations can be found at:
    #
    #  /model_name(plural)/id/association_name(singular)
    #
    # ==== Example
    #
    #  class Car < ActiveRecord::Base
    #    has_one_remote :engine
    #  end
    #
    #  car = Car.new(:id => 1)
    #  car.engine # => /cars/1/engine
    #
    #
    # == Many-to-one
    #
    # Use +belongs_to_remote+ to define a many-to-one relationship. That is, if the
    # model you're defining this on has a foreign key to the remote model.
    #
    # === URI Assumptions
    #
    # Remotely assumes all +belongs_to_remote+ associations can be found at:
    #
    #  /association_name(plural)/{association_name}_id
    #
    # ==== Example
    #
    #  class Car < ActiveRecord::Base
    #    belongs_to_remote :brand
    #  end
    #
    #  car = Car.new(:brand_id => 2)
    #  car.brand # => /brands/2
    #
    # == Options
    #
    # === +:path+
    # The full URI that should be used to fetch this resource.
    # (supported by all methods)
    #
    # === +:foreign_key+
    # The attribute that should be used, instead of +id+ when generating URIs.
    # (supported by +belongs_to_remote+ only)
    #
    # == Path Variables
    #
    # The +path+ option will replace any symbol(ish) looking string with the
    # value of that attribute, of the model.
    #
    #  class User < ActiveRecord::Base
    #    belongs_to_remote :family, :path => "/families/:family_key"
    #  end
    #
    #  user = User.new(:family_key => "noble")
    #  user.family # => /families/noble
    #
    module ClassMethods
      # Remote associations defined and their options.
      attr_accessor :remote_associations

      # Specifies a one-to-many relationship.
      #
      # @param [Symbol] name Name of the relationship
      # @param [Hash] options Association configuration options.
      # @option options [String] :path Path to the remote resource
      #
      def has_many_remote(name, options={})
        define_association_method(:has_many, name, options)
      end

      # Specifies a one-to-one relationship.
      #
      # @param [Symbol] name Name of the relationship
      # @param [Hash] options Association configuration options.
      # @option options [String] :path Path to the remote resource
      #
      def has_one_remote(name, options={})
        define_association_method(:has_one, name, options)
      end

      # Specifies a many-to-one relationship.
      #
      # @param [Symbol] name Name of the relationship
      # @param [Hash] options Association configuration options.
      # @option options [String] :path Path to the remote resource
      # @option options [Symbol, String] :foreign_key Attribute to be used
      #   in place of +id+ when constructing URIs.
      #
      def belongs_to_remote(name, options={})
        define_association_method(:belongs_to, name, options)
      end

    private

      def define_association_method(type, name, options)
        self.remote_associations     ||= {}
        self.remote_associations[name] = options.merge(type: type)
        define_method(name)        { |reload=false| call_association(reload, name) }
        define_method(:"#{name}=") { |o| set_association(name, o) }
      end

      def inherited(base)
        base.remote_associations = self.remote_associations
        base.extend(ClassMethods)
        base.extend(Remotely::HTTPMethods)
        super
      end
    end

    def remote_associations
      self.class.remote_associations ||= {}
    end

    def path_to(name, type)
      opts = remote_associations[name]
      raise HasManyForeignKeyError if opts[:foreign_key] && [:has_many, :has_one].include?(type)

      base = self.class.base_class.model_name.element.pluralize
      fkey = opts[:foreign_key] || :"#{name}_id"
      path = opts[:path]
      path = self.instance_exec(&path) if path.is_a?(Proc)

      # :path option takes precedence
      return interpolate URL(path) if path

      singular_path = name.to_s.singularize
      plural_path   = name.to_s.pluralize

      case type
      when :has_many
        interpolate URL(base, self.id, plural_path)
      when :has_one
        interpolate URL(base, self.id, singular_path)
      when :belongs_to
        interpolate URL(plural_path, public_send(fkey))
      end
    end

    def self.included(base) #:nodoc:
      base.extend(ClassMethods)
    end

  private

    def can_fetch_remotely_association?(name)
      opts = remote_associations[name]

      if opts[:path]
        opts[:path].scan(/:([^\/]*)/).map { |m| public_send(m.first.to_sym) }.all?
      else
        case opts[:type]
        when :belongs_to
          !public_send(opts[:foreign_key] || "#{name}_id").nil?
        when :has_many, :has_one
          !self.id.nil?
        end
      end
    end

    def call_association(reload, name)
      return get_association(name) unless can_fetch_remotely_association?(name)
      fetch_association(name) if reload || association_undefined?(name)
      get_association(name)
    end

    def fetch_association(name)
      opts = remote_associations[name]
      type       = remote_associations[name][:type]
      class_name = remote_associations[name][:class_name] if remote_associations[name][:class_name].present?
      klass      = (class_name || name).to_s.classify.constantize
      response   = klass.get(path_to(name, type), :class => klass, :parent => self)
      set_association(name, response)
    end

    def get_association(name)
      instance_variable_get("@#{name}")
    end

    def set_association(name, value)
      instance_variable_set("@#{name}", value)
    end

    def association_undefined?(name)
      !instance_variable_defined?("@#{name}")
    end

    def interpolate(content)
      content.to_s.gsub(/:\w+/) { |m| public_send(m.tr(":", "")) }
    end
  end
end
