#
# Common methods for all model classes within the application
#

module LadderModel

  module Core

    def self.included(base)
      base.send :include, Mongoid::Document

      # useful extras, see: http://mongoid.org/en/mongoid/docs/extras.html
      base.send :include, Mongoid::Paranoia # soft deletes
      base.send :include, Mongoid::Timestamps
      base.send :include, Mongoid::Tree

      # ElasticSearch integration
      base.send :include, Tire::Model::Search
      base.send :include, Tire::Model::Callbacks

      # Pagination
      base.send :include, Kaminari::MongoidExtension::Criteria
      base.send :include, Kaminari::MongoidExtension::Document

      # dynamic templates to store un-analyzed values for faceting
      base.send :mapping, :dynamic_templates => [{
          :test => {
              :match => '*',
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
      hash.each do |field, object|
        self.send(field.to_s + '=', object) if self.respond_to? field
      end
    end

    # Search the index and return a Tire::Collection of documents that have a similarity score
    def similar(query=false)
      return @similar unless query || @similar.nil?

      hash = self.dup.as_document.delete_if { |k,v| !v.is_a?(Hash) }
      id = self.id

      results = self.class.tire.search do
        query do
          boolean do
            hash.each do |vocab, vals|
              vals.each do |field, value|

                # don't include object IDs and arrays of object IDs
                next if value.is_a?(BSON::ObjectId)
                next if value.flatten.delete_if { |x| x.is_a?(BSON::ObjectId) }.empty?

                fieldname = "#{vocab}.#{field}"
                query_string = value.join(' ').gsub(/[-+!\(\)\{\}\[\]^"~*?:;,.\\]|&&|\|\|/, '')

                should do
                  text fieldname.to_sym, query_string
                end

                must_not do
                  term :_id, id
                end

              end
            end
          end
        end
        min_score 1
      end

      @similar = results
    end

    # Check similar documents and return an array of the subset that are identical
    def same(query=false)
      return @same unless query || @same.nil?

      @same = []

      self.similar(query).each do |similar|
        @same << similar if 0 == self.diff(similar).size
      end

      @same
    end

    # Return a HashDiff array computed between the two model instances
    def diff(model)
      normalize = lambda do |hash|
        hash.symbolize_keys!

        # strip id field
        hash.except! :_id

        # don't include object-id references in comparisons
        # NB: have to use regexp matching for Tire Items
        hash.delete_if {|key, value| value.flatten.delete_if { |x| x.is_a?(BSON::ObjectId) || x.to_s.match(/^[0-9a-f]{24}$/) }.empty?}

        hash.values.select{|v| v.is_a? Hash}.each{|h| normalize.call(h)}
        hash
      end

      test1 = normalize.call(self.as_document.reject { |key, value| !value.is_a? Hash })
      test2 = normalize.call(model.to_hash.reject { |key, value| !value.is_a? Hash })

      # return the diff comparison
      HashDiff.diff(test1, test2)
    end

    # Search an array of model fields in order and return the first non-empty value
    def get_first_field(fields_array)
      target = nil

      fields_array.each do |target_field|
        ns = target_field.split('.').first
        field = target_field.split('.').last

        target = self.send(ns).send(field)
        target = target.first if target.is_a? Array

        break if target
      end

      target
    end

    # more precise serialization for Tire
    def to_indexed_json
      mapping = self.class.tire.mapping

      # Reject keys not declared in mapping
      hash = self.attributes.reject { |key, value| ! mapping.keys.map(&:to_s).include?(key.to_s) }

      # Reject empty values
      hash = hash.reject { |key, value| value.kind_of? Enumerable and value.empty? }

      hash.to_json
    end

  end

  module Embedded

    def self.included(base)
      base.send :include, Mongoid::Document
      base.send :include, Easel::Bindable
    end

  end

end

#
# compress/encode imported data to save space/memory in Mongo
#

class CompressedBinary
  include Mongoid::Fields::Serializable

  def serialize(string)
    # compress string for storage
    string ? Base64.encode64(ActiveSupport::Gzip.compress(string)) : string
  end

  def deserialize(compressed)
    # decompress string
    compressed ? ActiveSupport::Gzip.decompress(Base64.decode64(compressed)) : compressed
  end

end