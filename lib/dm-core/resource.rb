module DataMapper
  module Resource
    include Extlib::Assertions
    extend Chainable

    def self.append_inclusions(*inclusions)
      warn "DataMapper::Resource.append_inclusions is deprecated, use DataMapper::Model.append_inclusions instead"
      Model.append_inclusions(*inclusions)
    end

    def self.extra_inclusions
      warn "DataMapper::Resource.extra_inclusions is deprecated, use DataMapper::Model.extra_inclusions instead"
      Model.extra_inclusions
    end

    def self.descendants
      warn "DataMapper::Resource.descendants is deprecated, use DataMapper::Model.descendants instead"
      DataMapper::Model.descendants
    end

    ##
    # Makes sure a class gets all the methods when it includes Resource
    #
    # @api private
    def self.included(model)
      model.extend Model
    end

    # Collection this resource associated with.
    # Used by SEL.
    #
    # @api private
    attr_writer :collection

    # @api public
    alias_method :model, :class

    ##
    # Returns the value of the attribute.
    #
    # Do not read from instance variables directly, but use this method.
    # This method handles lazy loading the attribute and returning of
    # defaults if nessesary.
    #
    #   Class Foo
    #     include DataMapper::Resource
    #
    #     property :first_name, String
    #     property :last_name,  String
    #
    #     def full_name
    #       "#{attribute_get(:first_name)} #{attribute_get(:last_name)}"
    #     end
    #
    #     # using the shorter syntax
    #     def name_for_address_book
    #       "#{last_name}, #{first_name}"
    #     end
    #   end
    #
    # @param  [Symbol] name
    #   name of attribute to retrieve
    #
    # @return [Object]
    #   the value stored at that given attribute
    #   (nil if none, and default if necessary)
    #
    # @api public
    def attribute_get(name)
      properties[name].get(self)
    end

    alias [] attribute_get

    ##
    # Sets the value of the attribute and marks the attribute as dirty
    # if it has been changed so that it may be saved. Do not set from
    # instance variables directly, but use this method. This method
    # handles the lazy loading the property and returning of defaults
    # if nessesary.
    #
    #   Class Foo
    #     include DataMapper::Resource
    #
    #     property :first_name, String
    #     property :last_name,  String
    #
    #     def full_name(name)
    #       name = name.split(' ')
    #       attribute_set(:first_name, name[0])
    #       attribute_set(:last_name, name[1])
    #     end
    #
    #     # using the shorter syntax
    #     def name_from_address_book(name)
    #       name = name.split(', ')
    #       first_name = name[1]
    #       last_name = name[0]
    #     end
    #   end
    #
    # @param [Symbol] name
    #   name of attribute to set
    # @param [Object] value
    #   value to store
    #
    # @return [Object]
    #   the value stored at that given attribute, nil if none,
    #   and default if necessary
    #
    # @api public
    def attribute_set(name, value)
      properties[name].set(self, value)
    end

    alias []= attribute_set

    ##
    # Compares another Resource for equality
    #
    # Resource is equal to +other+ if they are the same object (identity)
    # or if they are both of the *same model* and all of their attributes
    # are equivalent
    #
    # @param [Resource] other
    #   the other Resource to compare with
    #
    # @return [TrueClass, FalseClass]
    #   true if they are equal, false if not
    #
    # @api public
    def eql?(other)
      if equal?(other)
        return true
      end

      unless model.equal?(other.class)
        return false
      end

      cmp?(other, :eql?)
    end

    ##
    # Compares another Resource for equivalency
    #
    # Resource is equal to +other+ if they are the same object (identity)
    # or if they are both of the *same base model* and all of their attributes
    # are equivalent
    #
    # @param [Resource] other
    #   the other Resource to compare with
    #
    # @return [TrueClass, FalseClass]
    #   true if they are equivalent, false if not
    #
    # @api public
    def ==(other)
      if equal?(other)
        return true
      end

      unless other.respond_to?(:model) && model.base_model.equal?(other.model.base_model)
        return false
      end

      cmp?(other, :==)
    end

    ##
    # Compares two Resources to allow them to be sorted
    #
    # @param [Resource] other
    #   The other Resource to compare with
    #
    # @return [Integer]
    #   Return 0 if Resources should be sorted as the same, -1 if the
    #   other Resource should be after self, and 1 if the other Resource
    #   should be before self
    #
    # @api public
    def <=>(other)
      unless other.kind_of?(model)
        raise ArgumentError, "Cannot compare a #{other.model} instance with a #{model} instance"
      end
      cmp = 0
      model.default_order(repository_name).map do |i|
        cmp = i.property.get!(self) <=> i.property.get!(other)
        cmp *= -1 if i.direction == :desc
        break if cmp != 0
      end
      cmp
    end

    # Returns hash value of the object.
    # Two objects with the same hash value assumed equal (using eql? method)
    #
    # DataMapper resources are equal when their models have the same hash
    # and they have the same set of properties
    #
    # When used as key in a Hash or Hash subclass, objects are compared
    # by eql? and thus hash value has direct effect on lookup
    #
    # @api private
    def hash
      model.hash + key.hash
    end

    ##
    # Get a Human-readable representation of this Resource instance
    #
    #   Foo.new   #=> #<Foo name=nil updated_at=nil created_at=nil id=nil>
    #
    # @return [String]
    #   Human-readable representation of this Resource instance
    #
    # @api public
    def inspect
      attrs = properties.map do |property|
        value = if property.loaded?(self)
          property.get!(self).inspect
        elsif saved?
          '<not loaded>'
        else
          'nil'
        end

        "#{property.instance_variable_name}=#{value}"
      end

      "#<#{model.name} #{attrs * ' '}>"
    end

    ##
    # Repository this resource belongs to in the context of this collection
    # or of the resource's class.
    #
    # @return [Repository]
    #   the respository this resource belongs to, in the context of
    #   a collection OR in the instance's Model's context
    #
    # @api semipublic
    def repository
      # only set @repository explicitly when persisted
      defined?(@repository) ? @repository : model.repository
    end

    ##
    # Retrieve the key(s) for this resource.
    #
    # This always returns the persisted key value,
    # even if the key is changed and not yet persisted.
    # This is done so all relations still work.
    #
    # @return [Array(Key)]
    #   the key(s) identifying this resource
    #
    # @api public
    def key
      return @key if defined?(@key)

      key = model.key(repository_name).map do |property|
        original_values[property] || (property.loaded?(self) ? property.get!(self) : nil)
      end

      # set the key if every entry is non-nil
      @key = key if key.all?
    end

    ##
    # Checks if an attribute has been loaded from the repository
    #
    #   class Foo
    #     include DataMapper::Resource
    #
    #     property :name,        String
    #     property :description, Text,   :lazy => false
    #   end
    #
    #   Foo.new.attribute_loaded?(:description)   #=> false
    #
    # @return [TrueClass, FalseClass]
    #   true if ivar +name+ has been loaded
    #
    # @return [TrueClass, FalseClass] true if ivar +name+ has been loaded
    #
    # @api private
    def attribute_loaded?(name)
      properties[name].loaded?(self)
    end

    ##
    # Fetches all the names of the attributes that have been loaded,
    # even if they are lazy but have been called
    #
    #   class Foo
    #     include DataMapper::Resource
    #
    #     property :name,        String
    #     property :description, Text,   :lazy => false
    #   end
    #
    #   Foo.new.loaded_attributes   #=>  [ #<Property @model=Foo @name=:name> ]
    #
    # @return [Array(Property)]
    #   names of attributes that have been loaded
    #
    # @api private
    def loaded_attributes
      properties.select { |p| p.loaded?(self) }
    end

    ##
    # Hash of original values of attributes that have unsaved changes
    #
    # @return [Hash]
    #   original values of attributes that have unsaved changes
    #
    # @api semipublic
    def original_values
      @original_values ||= {}
    end

    ##
    # Hash of attributes that have unsaved changes
    #
    # @return [Hash]
    #   attributes that have unsaved changes
    #
    # @api semipublic
    def dirty_attributes
      dirty_attributes = {}

      original_values.each_key do |property|
        dirty_attributes[property] = property.value(property.get!(self))
      end

      dirty_attributes
    end

    ##
    # Checks if the resource has unsaved changes
    #
    # @return
    #   [TrueClass, FalseClass] true if resource is new or has any unsaved changes
    #
    # @api semipublic
    def dirty?
      if dirty_attributes.any?
        true
      elsif new?
        model.identity_field || properties.any? { |p| p.default? }
      else
        false
      end
    end

    ##
    # Checks if an attribute has unsaved changes
    #
    # @param [Symbol] name
    #   name of attribute to check for unsaved changes
    #
    # @return [TrueClass, FalseClass]
    #   true if attribute has unsaved changes
    #
    # @api semipublic
    def attribute_dirty?(name)
      dirty_attributes.key?(properties[name])
    end

    # Gets a Collection with the current Resource instance as its only member
    #
    # @return [Collection, FalseClass]
    #   false if this is a new record,
    #   otherwise a Collection with self as its only member
    #
    # @api private
    def collection
      @collection ||= if saved?
        Collection.new(to_query, [ self ])
      end
    end

    ##
    # Reloads association and all child association
    #
    # @return [Resource]
    #   the receiver, the current Resource instance
    #
    # @api public
    def reload
      if saved?
        reload_attributes(*loaded_attributes)
        child_associations.each { |a| a.reload }
      end

      self
    end

    ##
    # Reloads specified attributes
    #
    # @param [Enumerable(Symbol)] attributes
    #   name(s) of attribute(s) to reload
    #
    # @return [Resource]
    #   the receiver, the current Resource instance
    #
    # @api private
    def reload_attributes(*attributes)
      unless attributes.empty? || new?
        collection.reload(:fields => attributes)
      end

      self
    end

    ##
    # Checks if this Resource instance is new
    #
    # @return [TrueClass, FalseClass]
    #   true if the resource is new and not saved
    #
    # @api public
    def new?
      !saved?
    end

    ##
    # Checks if this Resource instance has been saved
    #
    # @deprecated
    def new_record?
      warn "#{model}#new_record? is deprecated, use #{model}#new? or #{model}#saved? instead"
      new?
    end

    ##
    # Checks if this Resource instance is saved
    #
    # @return [TrueClass, FalseClass]
    #   true if the resource has been saved
    #
    # @api public
    def saved?
      @saved == true
    end

    ##
    # Gets all the attributes of the Resource instance
    #
    # @return [Hash]
    #   All the (non)-lazy attributes
    #
    # @return [Hash]
    #   All the (non)-lazy attributes
    #
    # @api public
    def attributes
      attributes = {}
      properties.each do |property|
        if public_method?(name = property.name)
          attributes[name] = send(name)
        end
      end
      attributes
    end

    ##
    # Assign values to multiple attributes in one call (mass assignment)
    #
    # @param [Hash] attributes
    #   names and values of attributes to assign
    #
    # @return [Hash]
    #   names and values of attributes assigned
    #
    # @api public
    def attributes=(attributes)
      attributes.each do |name,value|
        if public_method?(setter = "#{name}=")
          send(setter, value)
        else
          raise ArgumentError, "The property '#{name}' is not accessible in #{model}"
        end
      end
    end

    ##
    # Deprecated API for updating attributes and saving Resource
    #
    # @see #update
    #
    # @api public
    def update_attributes(attributes = {}, *allowed)
      warn "#{model}#update_attributes is deprecated, use #{model}#update instead"

      if allowed.any?
        warn "specifying allowed in #{model}#update_attributes is deprecated," \
          'use Hash#only to filter the attributes in the caller'
        attributes = attributes.only(*allowed)
      end

      update(attributes, *allowed)
    end

    ##
    # Updates attributes and saves this Resource instance
    #
    # @param  [Hash]  attributes
    #   attributes to be updated
    #
    # @return [TrueClass, FalseClass]
    #   true if resource and storage state match
    #
    # @api public
    def update(attributes = {})
      assert_kind_of 'attributes', attributes, Hash

      self.attributes = attributes

      _update
    end

    ##
    # Save the instance and associated children to the data-store.
    #
    # This saves all children in a has n relationship (if they're dirty).
    #
    # @return [TrueClass, FalseClass]
    #   true if Resource instance and all associations were saved
    #
    # @see Repository#save
    #
    # @api public
    chainable do
      def save
        # Takes a context, but does nothing with it. This is to maintain the
        # same API through out all of dm-more. dm-validations requires a
        # context to be passed

        unless saved = new? ? _create : _update
          return false
        end

        child_associations.all? { |a| a.save }
      end
    end

    ##
    # Destroy the instance, remove it from the repository
    #
    # @return [TrueClass, FalseClass]
    #   true if resource was destroyed
    #
    # @api public
    def destroy
      if saved? && repository.delete(to_query) == 1
        reset
        true
      else
        false
      end
    end

    # Gets a Query that will return this Resource instance
    #
    # @return [Query] Query that will retrieve this Resource instance
    #
    # @api private
    def to_query
      model.to_query(repository, key)
    end

    ##
    # Reset the Resource to a similar state as a new record:
    # removes it from identity map and clears original property
    # values (thus making all properties non dirty)
    #
    # @api private
    def reset
      @saved = false
      identity_map.delete(key)
      original_values.clear
    end

    protected

    ##
    # Saves this Resource instance to the repository,
    # setting default values for any unset properties
    #
    # If resource is not dirty or a new (not yet saved),
    # this method returns false
    #
    # On successful save identity map of the repository is
    # updated
    #
    # Needs to be a protected method so that it is hookable
    #
    # @return [TrueClass, FalseClass]
    #   true if the receiver was successfully created
    #
    # @api semipublic
    def _create
      # Can't create a resource that is not dirty and doesn't have serial keys
      if new? && !dirty?
        return false
      end

      # set defaults for new resource
      properties.each do |property|
        unless property.serial? || property.loaded?(self)
          property.set(self, property.default_for(self))
        end
      end

      if created = (repository.create([ self ]) == 1)
        @repository = repository
        @saved      = true

        original_values.clear

        identity_map[key] = self
      end

      created
    end

    # Persists dirty attributes
    #
    # If object is not dirty, this method returns false.
    # If there are non-nullable properties with value of nil,
    # false is returned as well.
    #
    # This method updates identitity map of repository
    # this object was loaded from, and clears cached key
    # value (instance variable @key)
    #
    # @return [TrueClass, FalseClass]
    #   true if the receiver was successfully updated
    #
    # @api semipublic
    def _update
      # retrieve the attributes that need to be persisted
      dirty_attributes = self.dirty_attributes

      if dirty_attributes.empty?
        true
      elsif dirty_attributes.any? { |p,v| !p.nullable? && v.nil? }
        false
      else
        if updated = (repository.update(dirty_attributes, to_query) == 1)
          original_values.clear

          # remove the cached key in case it was updated
          remove_instance_variable(:@key)

          identity_map[key] = self
        end

        updated
      end
    end

    private

    # Returns name of the repository this object
    # was loaded from
    #
    # @return [String] name of the repository this object was loaded from
    #
    # @api private
    def repository_name
      repository.name
    end

    # Gets this instance's Model's properties
    #
    # @return [Array(Property)]
    #   List of this Resource's Model's properties
    #
    # @api private
    def properties
      model.properties(repository_name)
    end

    # Gets this instance's Model's relationships
    #
    # @return [Array(Associations::Relationship)]
    #   List of this instance's Model's Relationships
    #
    # @api private
    def relationships
      model.relationships(repository_name)
    end

    # Returns identity map of repository this object
    # was loaded from
    #
    # @return [DataMapper::IdentityMap]
    #   identity map of repository this object was loaded from
    #
    # @api semipublic
    def identity_map
      repository.identity_map(model)
    end

    ##
    # Initialize a new instance of this Resource using the provided values
    #
    # @param  [Hash] attributes
    #   attribute values to use for the new instance
    #
    # @return [Resource]
    #   the newly initialized resource instance
    #
    # @api public
    def initialize(attributes = {}) # :nodoc:
      @saved = false
      self.attributes = attributes
    end

    # Reloads attributes that belong to given lazy loading
    # context, and not yet loaded
    #
    # @api private
    def lazy_load(name)
      reload_attributes(*properties.lazy_load_context(name) - loaded_attributes)
    end

    # Returns array of child relationships for which this resource is parent and is loaded
    #
    # @return [Array<DataMapper::Associations::ManyToOne::Relationship>]
    #   array of child relationships for which this resource is parent and is loaded
    #
    # @api private
    def child_associations
      child_associations = []

      relationships.each_value do |r|
        next unless !r.kind_of?(Associations::ManyToOne::Relationship) && r.loaded?(self) && association = r.get!(self)
        child_associations << association
      end

      child_associations.freeze
    end

    ##
    # Return true if the reader or writer +method+ is publicly accessible
    #
    # @param [String, Symbol] method
    #   The name of reader or writer to test
    #
    # @return [TrueClass, FalseClass]
    #   true if the reader or writer +method+ is public
    #
    # @api private
    def public_method?(method)
      model.public_method_defined?(method)
    end

    ##
    # Return true if +other+'s is equivalent or equal to +self+'s
    #
    # @param [Resource] other
    #   The Resource whose attributes are to be compared with +self+'s
    # @param [Symbol] operator
    #   The comparison operator to use to compare the attributes
    #
    # @return [TrueClass, FalseClass]
    #   The result of the comparison of +other+'s attributes with +self+'s
    #
    # @api private
    def cmp?(other, operator)
      unless key.send(operator, other.key)
        return false
      end

      if repository.send(operator, other.repository) && !dirty? && !other.dirty?
        return true
      end

      # get all the loaded and non-loaded properties that are not keys,
      # since the key comparison was performed earlier
      loaded, not_loaded = properties.select { |p| !p.key? }.partition do |property|
        property.loaded?(self) && property.loaded?(other)
      end

      # check all loaded properties, and then all unloaded properties
      (loaded + not_loaded).all? { |p| p.get(self).send(operator, p.get(other)) }
    end
  end # module Resource
end # module DataMapper
