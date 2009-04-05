module DataMapper
  class Callsite

    # Callsite class represents a callsite container that tracks fields and links for a 
    # given model and repository.
    #
    
    Mtx = Mutex.new
    
    ##
    # Returns model (class) that is associated with this callsite
    #
    # @return [Model]
    #   the Model associated with this callsite
    #
    # @api semipublic    
    attr_reader :model 

    ##
    # Returns the repository name that is associated with this callsite
    #
    # @return [Symbol]
    #   the repository name associated with this callsite
    #
    # @api semipublic        
    attr_reader :repository_name
    
    ##
    # Returns the signature that is associated with this callsite
    #
    # @return [Symbol]
    #   the signature associated with this callsite
    #
    # @api semipublic    
    attr_reader :signature
    
    ##
    # Initializes a Callsite instance
    #
    # @example
    #
    #  DataMapper::Callsite.new( Product, :default, 12345 )
    #
    # @param [Model] model
    #   the Model associated with this callsite
    # @param [Symbol] repository_name
    #   the Repository name associated with this callsite
    # @param [Numeric] signature
    #   the Signature for this callsite
    #
    # @api semipublic    
    def initialize( model, repository_name, signature )
      @model = model      
      @repository_name = repository_name
      @signature = signature
      log_callsite
    end

    ##
    # Is the Model for this callsite inheritable ?
    #
    # @return [Boolean]
    #   true if inheritable
    #
    # @api public    
    def inheritable?
      !inheritance_field.nil?
    end

    ##
    # The inheritance field for the associated Model
    #
    # @return [Symbol]
    #   The inheritance field for the associated Model
    #
    # @api public    
    def inheritance_field
      @inheritance_field ||= init_inheritance_field
    end

    ##
    # The identity field for the associated Model
    #
    # @return [Symbol]
    #   The identity field for the associated Model
    #
    # @api public
    def identity_field
      @identify_field ||= init_identity_field
    end
    
    ##
    # Fields for this callsite and associated Model
    #
    # @return [Set]
    #   A set of fields associated with this callsite
    #
    # @api public    
    def fields
      @fields ||= init_fields
    end

    ##
    # Links for this callsite and associated Model
    #
    # @return [Set]
    #   A set of links associated with this callsite
    #
    # @api public    
    def links
      @links ||= init_links
    end

    ##
    # Is there any links associated with this callsite ?
    #
    # @return [Boolean]
    #   true if there's any links
    #
    # @api public        
    def links?
      !links.empty?
    end
    
    ##
    # Optimize a given Query instance with fields and links associated with this callsite.
    #
    # @param [Query] query
    #   a Query instance
    #
    # @return [Query]
    #   a Query instance augmented with callsite data
    #
    # @api semipublic    
    def optimize( query )
      query.update( to_hash )
    end  

    ##
    # Query representation
    #
    # @return [Query]
    #   a Query instance for the associated Model, repository that respects registered fields 
    #   and links
    #
    # @api public    
    def to_query
      DataMapper::Query.new( DataMapper.repository(@repository_name), @model, to_hash )
    end  

    ##
    # Hash representation
    #
    # @return [Hash]
    #   a Hash suitable as an argument to Query#update, Query#merge and Query#new
    #
    # @api public    
    def to_hash
      if links?
        { :fields => fields.to_a, :links => links.to_a }
      else  
        { :fields => fields.to_a }
      end
    end  
    
    private

      ##
      # Lazy init default fields
      #
      # @return [Set]
      #   A collection of default fields
      #
      # @api private
      def init_fields
        Set.new( @model.properties.defaults.map{|p| p.name } )
      end

      ##
      # Lazy init links
      #
      # @return [Set]
      #   A collection of default links
      #
      # @api private  
      def init_links
        Set.new
      end

      ##
      # Lazy init the identity field
      #
      # @return [Symbol]
      #   the identity field
      # @return [NilClass]
      #   if no identify field is defined for the Model
      #
      # @api private    
      def init_identity_field
        field_name @model.identity_field
      end

      ##
      # Lazy init the inheritance field
      #
      # @return [Symbol]
      #   the inheritance field
      # @return [NilClass]
      #   if no inheritance field is defined for the Model
      #
      # @api private    
      def init_inheritance_field
        field_name @model.properties.detect{|p| p.type == Class }
      end

      ##
      # Returns the field name from a given property
      #
      # @param [Property]
      #   a property insance
      # @param [NilClass]  
      #   nil if no property could be found   
      #
      # @return [Symbol]
      #   the property name
      # @return [NilClass]
      #   if the property is nil, no name
      #
      # @api private     
      def field_name( property )
        property ? property.name : nil
      end  

      ##
      # Logs the new callsite
      #
      # @api private     
      def log_callsite
        DataMapper.logger.debug "New callsite #{@signature.inspect} for model #{@model.inspect}, instantiated from repository #{@repository_name.inspect}"
      end
      
  end
end