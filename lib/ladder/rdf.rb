require_relative 'model'

module Ladder

  class RDF
    include Ladder::Model
    use_vocab ::RDF::RDFS
    store_in collection: 'models'
    
    # Create a Model class bound to specific vocabs
    #
    # Required parameters:
    # :name (String)  -> the name of the model class to create
    # :module (String) -> the name of a module to namespace classes within
    # :vocabs (Array:String) -> a list of RDF::Vocabulary classes to use
    # :types (Array:String) -> a list of prefixed RDF classes to assign

    def self.model(*args)
      opts = args.last || {}
      opts.symbolize_keys!

      return unless name = opts[:name] and mod = opts[:module] and vocabs = opts[:vocabs] and types = opts[:types]
      return unless mod.is_a? String
      return unless vocabs.is_a? Array
      return unless types.is_a? Array

      # If this Module is already defined, use it
      namespace = if Object.const_defined? mod.classify and mod.classify.constantize.is_a? Module
        mod.classify.constantize
      else
        Object.const_set mod.classify, Module.new
      end

      # If this Class is already modeled, return it
      return namespace.const_get name.classify if namespace.const_defined? name.classify and namespace.const_get(name.classify).is_a? Class

      klass = namespace.const_set name.classify, Class.new(self)
      
      # Assign vocabs first so we know which RDF types are valid
      vocabs.each do |vocab|
        # Only allow valid RDF::Vocabulary classes
        klass.use_vocab vocab.constantize if Object.const_defined? vocab
      end
      
      valid_types = types.map do |type|
        vocab, property = type.split('.')

        next unless Object.const_defined? vocab
        next unless vocab.constantize.class_properties.include? property.to_sym
        # next unless vocab.constantize.respond_to? property
        
        type
      end

      # Array of rdf:type values for Classes
        field :types, type: Array, default: valid_types.uniq.compact
      klass
    end

  end

end