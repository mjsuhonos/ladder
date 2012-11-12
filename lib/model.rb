#
# Common methods for all model classes within the application
#

module LadderModel

  module Core

    module ClassMethods

      def define_scopes
        embeddeds = self.reflect_on_all_associations(*[:embeds_one])

        embeddeds.each do |embed|
          scope embed.name, ->(exists=true) { where(embed.name.exists => exists) }
        end
      end

      # TODO: boost results in heading fields (title, alternative, etc)
      def define_indexes(vocabs = {})
        embeddeds = self.reflect_on_all_associations(*[:embeds_one])

        embeddeds.each do |embed|

          # mongodb index definitions
          embed.class_name.constantize.fields.each do |field|

            if field.is_a? Array
              if vocabs.empty?
                # default to indexing all fields
                index "#{embed.key}.#{field.first}" => 1

              elsif !vocabs[embed.name].nil? and vocabs[embed.name].include? field.first.to_sym
                # only index defined fields
                index "#{embed.key}.#{field.first}" => 1
              end

            end
          end

          # elasticsearch index definitions
          mapping indexes embed.name, :type => 'object'
        end

      end

      # Override Mongoid #find_or_create_by
      # @see: http://rdoc.info/github/mongoid/mongoid/Mongoid/Finders
      def find_or_create_by(attrs = {}, &block)

        # build a query based on nested fields
        query = self

        attrs.each do |vocab, vals|
          vals.each do |field, value|
            query = query.and("#{vocab}.#{field}" => value) unless value.empty?
          end
        end

        unless query.instance_of? Class
          # if a document exists, return that
          result = query.first

          return result unless result.nil?
        end

        # otherwise create and return a new object
        obj = self.new(attrs)
        obj.save
        obj
      end

      def normalize(hash, opts={})
        # use a deep clone of the hash
        hash = Marshal.load(Marshal.dump(hash))

        # store relation ids if we need to resolve them
        if :resolve == opts[:ids]
          hash.symbolize_keys!

          opts[:type] = hash[:type] || self.name.underscore
          opts[:resource_ids] = hash[:resource_ids]
          opts[:agent_ids] = hash[:agent_ids]
          opts[:concept_ids] = hash[:concept_ids]
        end

        # Reject keys not declared in mapping
        hash.reject! { |key, value| ! self.tire.mapping.keys.include? key.to_sym }

        # Self-contained recursive lambda
        normal = lambda do |hash, opts|

          hash.symbolize_keys!

          # Strip id field
          hash.except! :_id

          # Modify Object ID references if specified
          if hash.class == Hash and opts[:ids]

            hash.each do |key, values|
              values.to_a.each do |value|

                # NB: have to use regexp matching for Tire Items
                if value.is_a? BSON::ObjectId or value.to_s.match(/^[0-9a-f]{24}$/)

                  case opts[:ids]
                    when :omit then
                      #hash[key].delete value     # doesn't work as expected?
                      hash[key][values.index(value)] = nil

                    when :resolve then
                      model = :resource if opts[:resource_ids].include? value rescue nil
                      model = :agent if opts[:agent_ids].include? value rescue nil
                      model = :concept if opts[:concept_ids].include? value rescue nil
                      model = opts[:type].to_sym if model.nil?

                      hash[key][values.index(value)] = {model => value.to_s}
                  end
                end
              end

              # remove keys that are now empty
              hash[key].to_a.compact!
            end

          end

          # Reject empty values
          hash.reject! { |key, value| value.kind_of? Enumerable and value.empty? }

          hash.values.select { |value| value.is_a? Hash }.each{ |h| normal.call(h, opts) }
          hash
        end

        normal.call(hash.reject { |key, value| !value.is_a? Hash }, opts)
      end

      def chunkify(opts = {})
        Mongoid::Criteria.new(self).chunkify(opts)
      end

    end

    def self.included(base)
      base.send :include, Mongoid::Document

      # useful extras, see: http://mongoid.org/en/mongoid/docs/extras.html
      base.send :include, Mongoid::Paranoia # soft deletes
      base.send :include, Mongoid::Timestamps
      base.send :include, Mongoid::Tree
#      base.send :include, Mongoid::Tree::Ordering

      # Pagination
      base.send :include, Kaminari::MongoidExtension::Criteria
      base.send :include, Kaminari::MongoidExtension::Document

      # ElasticSearch integration
      base.send :include, Tire::Model::Search
      base.send :include, Tire::Model::Callbacks2 # local patched version

      # dynamic templates to store un-analyzed values for faceting
      # @see line:19 ; remove dynamic templates and use explicit mapping
      base.send :mapping, :dynamic_templates => [{
          :test => {
              :match => '*',
              :match_mapping_type => 'string',
              :mapping => {
                  :type => 'multi_field',
                  :fields => {
                      '{name}' => {
                          :type => '{dynamic_type}',
                          :index => 'analyzed'
                      },
                      :raw => {
                          :type => '{dynamic_type}',
                          :index => 'not_analyzed'
                      }
                  }
              }
          }
        }], :_source => { :compress => true } do

      # Timestamp information
      base.send :indexes, :created_at,    :type => 'date'
      base.send :indexes, :deleted_at,    :type => 'date'
      base.send :indexes, :updated_at,    :type => 'date'

      # Hierarchy information
      base.send :indexes, :parent_id,     :type => 'string'
      base.send :indexes, :parent_ids,    :type => 'string'

      # Relation information
      base.send :indexes, :agent_ids,     :type => 'string'
      base.send :indexes, :concept_ids,   :type => 'string'
      base.send :indexes, :resource_ids,  :type => 'string'

      # add useful class methods
      base.extend ClassMethods
    end

  end

    # Retrieve a hash of field names and embedded vocab objects
    def vocabs
      embeddeds = self.reflect_on_all_associations(*[:embeds_one])

      vocabs = {}
      embeddeds.each do |embedded|
        vocab = self.method(embedded.key).call
        vocabs[embedded.key.to_sym] = vocab unless vocab.nil?
      end

      vocabs
    end

    # Assign model vocab objects by a hash of field names
    def vocabs=(hash)
      self.update_attributes(hash)
    end

    # Search the index and return a Tire::Collection of documents that have a similarity score
    def similar(query=false)
      return @similar unless query || @similar.nil?

      hash = self.class.normalize(self.as_document)
      id = self.id

      results = self.class.tire.search do
        query do
          boolean do
            # do not include self
            must_not { term :_id, id }

            hash.each do |vocab, vals|
              vals.each do |field, value|

                query_string = value.join(' ').gsub(/[-+!\(\)\{\}\[\]\n^"~*?:;,.\\\/]|&&|\|\|/, '')
                should { text "#{vocab}.#{field}", query_string }

              end
            end
          end
        end
        min_score 1
      end

      @similar = results
    end

    # Return a HashDiff array computed between the two model instances
    def diff(model)
      # use the right type for masqueraded search results
      if model.is_a? Tire::Results::Item
        compare = model.to_hash
      else
        compare = model.as_document
      end

      # return the diff comparison
      HashDiff.diff(self.class.normalize(self.as_document), self.class.normalize(compare))
    end

    def amatch(model, opts={})
      options = {:hamming_similar => true,
                 :jaro_similar => true,
                 :jarowinkler_similar => true,
                 :levenshtein_similar => true,
                 :longest_subsequence_similar => true,
                 :longest_substring_similar => true,
                 :pair_distance_similar => true}

      # if we have selected specific comparisons, use those
      options = opts unless opts.empty?

      # use the right type for masqueraded search results
      if model.is_a? Tire::Results::Item
        compare = model.to_hash
      else
        compare = model.as_document
      end

      p1 = self.class.normalize(self.as_document, options.slice(:ids))
      p2 = self.class.normalize(compare, options.slice(:ids))

      p1 = p1.values.map(&:values).flatten.map(&:to_s).join(' ').gsub(/[-+!\(\)\{\}\[\]\n\s^"~*?:;,.\\\/]|&&|\|\|/, '')
      p2 = p2.values.map(&:values).flatten.map(&:to_s).join(' ').gsub(/[-+!\(\)\{\}\[\]\n\s^"~*?:;,.\\\/]|&&|\|\|/, '')

      # calculate amatch score for each algorithm
      options.delete :ids
      options.each do |sim, bool|
        options[sim] = p1.send(sim, p2) if bool
      end

      options
    end

    # Search an array of model fields in order and return the first non-empty value
    def get_first_field(fields_array)
      target = nil

      fields_array.each do |target_field|
        vocab = target_field.split('.').first
        field = target_field.split('.').last

        target = self.send(vocab).send(field) unless self.send(vocab).nil?

        break if target
      end

      target
    end

    # more precise serialization for Tire
    def to_indexed_json
      mapping = self.class.tire.mapping

      # Reject keys not declared in mapping
      hash = self.as_document.reject { |key, value| ! mapping.keys.include? key.to_sym }

      # Reject empty values
      hash = hash.reject { |key, value| value.kind_of? Enumerable and value.empty? }

      # add heading
      hash[:heading] = self.heading

      hash.to_json
    end

    def to_rdfxml(url)
      uri = URI.parse(url)

      # normalize into a hash to resolve ID references
      normal = self.class.normalize(self.as_document, {:ids => :resolve})

      normal.each do |name, vocab|
        vocab.each do |field, values|
          values.each do |value|
            if value.is_a? Hash
              # replace ID references with URI references
              normal[name][field][values.index(value)] = RDF::URI.new("#{uri.scheme}://#{uri.host}/#{value.keys.first}/#{value.values.first}")
            end
          end
        end
      end

      # create a new model object from the modified values
      new_obj = self.class.new(normal)

      RDF::RDFXML::Writer.buffer do |writer|
        # get the RDF graph for each vocab
        new_obj.vocabs.each do |key, object|
          writer << object.to_rdf(RDF::URI.new(url))
        end
      end

    end

  end

  module Embedded

    def self.included(base)
      base.send :include, Mongoid::Document
      base.send :include, Easel::Bindable
    end

  end

end