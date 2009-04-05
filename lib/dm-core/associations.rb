module DataMapper
  module Associations
    include Extlib::Assertions
    extend Chainable

    # Raised on attempt to operate on collection of child objects
    # when parent object is not yet saved.
    # For instance, if your article object is not saved,
    # but you try to fetch or scope down comments (1:n case), or
    # publications (n:m case), operation cannot be completed
    # because parent object's keys are not yet persisted,
    # and thus there is no FK value to use in the query.
    class UnsavedParentError < RuntimeError; end

    # Initializes relationships hash for extended model
    # class.
    #
    # When model calls has n, has 1 or belongs_to, relationships
    # are stored in that hash: keys are repository names and
    # values are relationship sets.
    #
    # @api private
    def self.extended(model)
      model.instance_variable_set(:@relationships, {})
    end

    chainable do
      # When DataMapper model is inherited, relationships
      # of parent are duplicated and copied to subclass model
      #
      # @api private
      def inherited(target)
        # TODO: Create a RelationshipSet class, and then add a method that allows copying the relationships to the supplied repository and model
        target.instance_variable_set(:@relationships, duped_relationships = {})

        @relationships.each do |repository_name, relationships|
          dup = duped_relationships[repository_name] ||= Mash.new

          relationships.each do |name, relationship|
            dup[name] = relationship.class.new(
              relationship.name,
              relationship.child_model_name  == self.name ? target : relationship.child_model_name,
              relationship.parent_model_name == self.name ? target : relationship.parent_model_name,
              relationship.options
            )
          end
        end

        super
      end
    end

    # Returns copy of relationships set in given repository.
    #
    # @param [Symbol] repository_name
    #   Name of the repository for which relationships set is returned
    # @return [Mash]  relationships set for given repository
    #
    # @api semipublic
    def relationships(repository_name = default_repository_name)
      assert_kind_of 'repository_name', repository_name, Symbol

      # TODO: create RelationshipSet#copy that will copy the relationships, but assign the
      # new Relationship objects to a supplied repository and model.  dup does not really
      # do what is needed

      @relationships[repository_name] ||= if repository_name == default_repository_name
        Mash.new
      else
        relationships(default_repository_name).dup
      end
    end

    # Used to express unlimited cardinality of association,
    # see +has+
    def n
      1.0/0
    end

    ##
    # A shorthand, clear syntax for defining one-to-one, one-to-many and
    # many-to-many resource relationships.
    #
    #  * has 1,    :friend    # one friend
    #  * has n,    :friends   # many friends
    #  * has 1..3, :friends   # many friends (at least 1, at most 3)
    #  * has 3,    :friends   # many friends (exactly 3)
    #  * has 1,    :friend,  :model   => 'User'       # one friend with the class User
    #  * has 3,    :friends, :through => :friendships # many friends through the friendships relationship
    #
    # @param cardinality [Integer, Range, Infinity]
    #   cardinality that defines the association type and constraints
    # @param name <Symbol>  the name that the association will be referenced by
    # @param opts <Hash>    an options hash
    #
    # @option :through[Symbol]  A association that this join should go through to form
    #       a many-to-many association
    # @option :model[Model,String] The name of the class to associate with, if omitted
    #       then the association name is assumed to match the class name
    # @option :repository[Symbol]
    #       name of child model repository
    #
    # @return [Association::Relationship] the relationship that was
    #   created to reflect either a one-to-one, one-to-many or many-to-many
    #   relationship
    # @raise [ArgumentError] if the cardinality was not understood. Should be a
    #   Integer, Range or Infinity(n)
    #
    # @api public
    def has(cardinality, name, options = {})
      assert_kind_of 'cardinality', cardinality, Integer, Range, n.class
      assert_kind_of 'name',        name,        Symbol
      assert_kind_of 'options',     options,     Hash

      min, max = extract_min_max(cardinality)
      options = options.merge(:min => min, :max => max)

      assert_valid_options(options)

      parent_repository_name = repository.name

      options[:child_repository_name]  = options.delete(:repository)
      options[:parent_repository_name] = parent_repository_name

      klass = if options.key?(:through)
        ManyToMany::Relationship
      elsif options[:max] > 1
        OneToMany::Relationship
      else
        OneToOne::Relationship
      end

      relationships(parent_repository_name)[name] = klass.new(name, options.delete(:model), self, options)
    end

    ##
    # A shorthand, clear syntax for defining many-to-one resource relationships.
    #
    #  * belongs_to :user                              # many to one user
    #  * belongs_to :friend, :model => 'User'          # many to one friend
    #  * belongs_to :reference, :repository => :pubmed # association for repository other than default
    #
    # @param name [Symbol] The name that the association will be referenced by
    # @see #has
    #
    # @option :model[Model,String] The name of the class to associate with, if omitted
    #       then the association name is assumed to match the class name
    #
    # @option :repository[Symbol]
    #       name of child model repository
    #
    # @return [Association::Relationship] The association created
    #   should not be accessed directly
    #
    # @api public
    def belongs_to(name, options = {})
      assert_kind_of 'name',    name,    Symbol
      assert_kind_of 'options', options, Hash

      options = options.dup

      assert_valid_options(options)

      child_repository_name = repository.name

      options[:child_repository_name]  = child_repository_name
      options[:parent_repository_name] = options.delete(:repository)

      relationships(child_repository_name)[name] = ManyToOne::Relationship.new(name, self, options.delete(:model), options)
    end

    private

    ##
    # A support method for converting Integer, Range or Infinity values into two
    # values representing the minimum and maximum cardinality of the association
    #
    # @return [Array]  A pair of integers, min and max
    #
    # @api private
    def extract_min_max(cardinality)
      case cardinality
        when Integer then [ cardinality,       cardinality      ]
        when Range   then [ cardinality.first, cardinality.last ]
        when n       then [ 0,                 n                ]
      end
    end

    # Validates options of association method like belongs_to or has:
    # verifies types of cardinality bounds, repository, association class,
    # keys and possible values of :through option.
    #
    # @api private
    def assert_valid_options(options)
      # TODO: update to match Query#assert_valid_options
      #   - perform options normalization elsewhere

      if options.key?(:min) && options.key?(:max)
        assert_kind_of 'options[:min]', options[:min], Integer
        assert_kind_of 'options[:max]', options[:max], Integer, n.class

        if options[:min] == n && options[:max] == n
          raise ArgumentError, 'Cardinality may not be n..n.  The cardinality specifies the min/max number of results from the association'
        elsif options[:min] > options[:max]
          raise ArgumentError, "Cardinality min (#{options[:min]}) cannot be larger than the max (#{options[:max]})"
        elsif options[:min] < 0
          raise ArgumentError, "Cardinality min much be greater than or equal to 0, but was #{options[:min]}"
        elsif options[:max] < 1
          raise ArgumentError, "Cardinality max much be greater than or equal to 1, but was #{options[:max]}"
        end
      end

      if options.key?(:repository)
        assert_kind_of 'options[:repository]', options[:repository], Repository, Symbol

        if options[:repository].kind_of?(Repository)
          options[:repository] = options[:repository].name
        end
      end

      if options.key?(:class_name)
        assert_kind_of 'options[:class_name]', options[:class_name], String
        warn '+options[:class_name]+ is deprecated, use :model instead'
        options[:model] = options.delete(:class_name)
      end

      if options.key?(:child_key)
        assert_kind_of 'options[:child_key]', options[:child_key], Enumerable
      end

      if options.key?(:parent_key)
        assert_kind_of 'options[:parent_key]', options[:parent_key], Enumerable
      end

      if options.key?(:through) && options[:through] != Resource
        assert_kind_of 'options[:through]', options[:through], Relationship, Symbol, Module

        if (through = options[:through]).kind_of?(Symbol)
          unless options[:through] = relationships(repository.name)[through]
            raise ArgumentError, "through refers to an unknown relationship #{through} in #{self} within the #{repository.name} repository"
          end
        end
      end

      if options.key?(:limit)
        raise ArgumentError, '+options[:limit]+ should not be specified on a relationship'
      end
    end

    Model.append_extensions self
  end # module Associations
end # module DataMapper
