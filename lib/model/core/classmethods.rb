#
# Class methods for all model classes within the application
#

module Model

  module Core

    module ClassMethods

      # Override Mongoid #find_or_create_by
      # @see: http://rdoc.info/github/mongoid/mongoid/Mongoid/Finders
      def find_or_create_by(attrs = {}, &block)

        # use md5 fingerprint to query if a document already exists
        hash = self.normalize(attrs, {:ids => :omit})
        query = self.where(:md5 => Moped::BSON::Binary.new(:md5, Digest::MD5.digest(hash.to_s)))

        result = query.first
        return result unless result.nil?

        # otherwise create and return a new object
        obj = self.new(attrs)
        obj.save
        obj
      end

      def chunkify(opts = {})
        Mongoid::Criteria.new(self).chunkify(opts)
      end

      def vocabs
        embeddeds = reflect_on_all_associations(*[:embeds_one])

        vocabs = {}
        embeddeds.each do |embedded|
          vocabs[embedded.key.to_sym] = embedded.class_name.constantize
        end

        vocabs
      end

      def define_scopes
        self.vocabs.keys.each do |vocab|
          scope vocab, ->(exists=true) { where(vocab.exists => exists) }
        end

        # add scope to check for documents not in ES index
        scope :unindexed, -> do

          # get the most recent timestamp
          s = self.search {
            query { all }
            sort { by :_timestamp, 'desc' }
            size 1
          }

          # if there's a timestamp in the index, use that as the offset
          unless s.results.empty?
            timestamp = s.results.first.sort.first / 1000
            self.queryable.or(:updated_at.gte => timestamp, :created_at.gte => timestamp)
          else
            self.queryable
          end
        end
      end

      def define_mapping
        # basic object mapping for vocabs
        # TODO: put explicit mapping here when removing dynamic templates
        vocabs = self.vocabs.each_with_object({}) do |(key,val), h|
          h[key] = {:type => 'object'}
        end

        # Timestamp information
        dates = [:created_at, :deleted_at, :updated_at].each_with_object({}) {|(key,val), h| h[key] = {:type => 'date'}}

        # Hierarchy/Group information
        ids = [:parent_id, :parent_ids, :group_ids].each_with_object({}) {|(key,val), h| h[key] = {:type => 'string'}}

        # Relation information
        relations = [:agent_ids, :concept_ids, :resource_ids].each_with_object({}) {|(key,val), h| h[key] = {:type => 'string'}}

        properties = {
            # Heading is what users will correlate with most
            :heading => {:type => 'string', :boost => 2},

            # RDF class information
            :rdf_types => {:type => 'multi_field', :fields => {
              'rdf_types' => { :type => 'string', :index => 'analyzed' },
              :raw        => { :type => 'string', :index => 'not_analyzed' }
              }
            },
        }.merge(vocabs).merge(dates).merge(ids).merge(relations)

        # store mapping as a class variable for future lookups
        @mapping = {:_source => { :compress => true },
                     :_timestamp => { :enabled => true },
                     :properties => properties,

                     # dynamic templates to store un-analyzed values for faceting
                     # TODO: remove dynamic templates and use explicit facet mapping
                     :dynamic_templates => [{
                         :auto_facet => {
                              :match => '*',
                              :match_mapping_type => '*',
                              :mapping => {
                                  :type => 'multi_field',
                                  :fields => {
                                      '{name}' => {
                                          :type => 'string',
                                          :index => 'analyzed'
                                      },
                                      :raw => {
                                          :type => 'string',
                                          :index => 'not_analyzed'
                                      }
                                  }
                              }
                          }
                     }]}
      end

      def put_mapping
        # ensure the index exists
        create_elasticsearch_index

        # do a PUT mapping for this index
        tire.index.mapping self.name.downcase, @mapping ||= self.define_mapping
      end

      def get_mapping
        @mapping ||= self.define_mapping
      end

      def normalize(hash, opts={})
        # Use a sorted deep duplicate of the hash
        hash = hash.deep_dup.sort_by_key(true)

        # store relation ids if we need to resolve them
        if :resolve == opts[:ids]
          hash.symbolize_keys!

          opts[:type] = hash[:type] || self.name.underscore
          opts[:resource_ids] = hash[:resource_ids]
          opts[:agent_ids] = hash[:agent_ids]
          opts[:concept_ids] = hash[:concept_ids]
        end

        # Reject keys not declared in mapping
        unless 'Group' == self.name
          hash.reject! { |key, value| ! self.get_mapping[:properties].keys.include? key.to_sym }
        end

        # Self-contained recursive lambda
        normal = lambda do |hash, opts|

          hash.symbolize_keys!

          # Strip id field
          hash.except! :_id
          hash.except! :rdf_types

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

          # Recurse into Hash values
          hash.values.select { |value| value.is_a? Hash }.each{ |h| normal.call(h, opts) }

          hash
        end

        normal.call(hash.reject { |key, value| !value.is_a? Hash }, opts)
      end

    end

  end

end